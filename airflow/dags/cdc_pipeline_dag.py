from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.sensors.glue import GlueJobSensor
from airflow.providers.amazon.aws.operators.sns import SnsPublishOperator
from airflow.operators.python import PythonOperator
from airflow.utils.trigger_rule import TriggerRule
import boto3
import requests
import os
import json


default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'retry_exponential_backoff': True,
    'max_retry_delay': timedelta(minutes=30),
    'execution_timeout': timedelta(hours=2),
    'sla': timedelta(hours=1)
}


dag = DAG(
    dag_id='cdc_pipeline_orchestration',
    default_args=default_args,
    description='CDC pipeline orchestration',
    schedule_interval=timedelta(hours=1),
    catchup=False,
    max_active_runs=1,
    tags=['cdc', 'debezium', 'kafka', 'glue', 'iceberg']
)


KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
DEBEZIUM_CONNECT_URL = os.getenv("DEBEZIUM_CONNECT_URL", "http://localhost:8083")
AWS_REGION = os.getenv("AWS_REGION", "ap-south-1")
S3_BUCKET = os.getenv("S3_BUCKET", "your-bucket")
GLUE_ROLE_NAME = os.getenv("GLUE_ROLE_NAME", "cdc-pipeline-dev-glue-role")


def check_kafka_health():
    try:
        print("Checking Kafka...")

        if "amazonaws" in KAFKA_BOOTSTRAP_SERVERS:
            msk = boto3.client('kafka', region_name=AWS_REGION)
            clusters = msk.list_clusters(MaxResults=1)
            print("MSK clusters visible:", len(clusters.get("ClusterInfoList", [])))

        health_url = None
        if ":9092" in KAFKA_BOOTSTRAP_SERVERS:
            health_url = KAFKA_BOOTSTRAP_SERVERS.replace(":9092", ":8090/health")

        if health_url:
            try:
                r = requests.get(health_url, timeout=5)
                if r.status_code == 200:
                    print("Kafka REST health OK")
            except Exception:
                pass

        print("Kafka check done")
        return True

    except Exception as e:
        raise Exception(f"Kafka health failed: {str(e)}")


def check_debezium_connectors(**context):
    try:
        print("Checking Debezium connectors...")

        session = requests.Session()
        r = session.get(f"{DEBEZIUM_CONNECT_URL}/connectors", timeout=10)
        r.raise_for_status()

        connectors = r.json()
        print("Connectors found:", connectors)

        statuses = {}

        for c in connectors:
            try:
                sr = session.get(f"{DEBEZIUM_CONNECT_URL}/connectors/{c}/status", timeout=10)
                sr.raise_for_status()
                st = sr.json()
                statuses[c] = {
                    "state": st.get("connector", {}).get("state", "UNKNOWN"),
                    "tasks": st.get("tasks", [])
                }
                print(c, "->", statuses[c]["state"])
            except Exception as e:
                statuses[c] = {"state": "UNKNOWN", "error": str(e)}

        context['task_instance'].xcom_push(key="connector_statuses", value=statuses)

        failed = [c for c, s in statuses.items() if s["state"] == "FAILED"]
        if failed:
            raise Exception(f"Failed connectors: {failed}")

        return True

    except Exception as e:
        raise Exception(f"Debezium check failed: {str(e)}")


def setup_debezium_connectors():
    try:
        print("Verifying Debezium connector config...")

        connector_config = {
            "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
            "database.hostname": os.getenv("DB_HOST", "localhost"),
            "database.port": os.getenv("DB_PORT", "5432"),
            "database.user": os.getenv("DB_USER", "postgres"),
            "database.password": os.getenv("DB_PASSWORD", "postgres"),
            "database.dbname": os.getenv("DB_NAME", "cdc_demo"),
            "database.server.name": "cdc-demo-server",
            "topic.prefix": "cdc",
            "table.include.list": "public.users,public.products,public.orders",
            "slot.name": "debezium_slot",
            "plugin.name": "pgoutput",
            "key.converter.schemas.enable": "false",
            "value.converter.schemas.enable": "false",
            "schema.history.internal.kafka.bootstrap.servers": KAFKA_BOOTSTRAP_SERVERS,
            "schema.history.internal.kafka.topic": "schema-changes.cdc-connector"
        }

        session = requests.Session()
        r = session.get(f"{DEBEZIUM_CONNECT_URL}/connectors/cdc-connector", timeout=10)

        if r.status_code == 200:
            print("Connector already exists")
        else:
            print("Creating connector...")
            cr = session.put(
                f"{DEBEZIUM_CONNECT_URL}/connectors/cdc-connector/config",
                json=connector_config,
                headers={"Content-Type": "application/json"},
                timeout=30
            )
            cr.raise_for_status()
            print("Connector created")

        return True

    except Exception as e:
        raise Exception(f"Connector setup failed: {str(e)}")


def monitor_data_quality(**context):
    ti = context['task_instance']
    statuses = ti.xcom_pull(key="connector_statuses", task_ids="debezium_health_check")

    metrics = {
        "timestamp": datetime.utcnow().isoformat(),
        "connectors_healthy": True,
        "connector_count": 0
    }

    if statuses:
        metrics["connector_count"] = len(statuses)
        for c, s in statuses.items():
            if s["state"] != "RUNNING":
                metrics["connectors_healthy"] = False
                print("Connector not running:", c, s["state"])

    ti.xcom_push(key="data_quality_metrics", value=metrics)
    print("Quality metrics:", metrics)

    if not metrics["connectors_healthy"]:
        raise Exception("Connectors not healthy")

    return True


def cleanup_failed_runs(**context):
    try:
        ti = context['task_instance']
        dag_run = ti.dag_run
        failed = [t for t in dag_run.get_task_instances() if t.state == 'failed']
        print("Failed tasks count:", len(failed))
        return True
    except Exception as e:
        print("Cleanup issue:", str(e))
        return False


kafka_health_check = PythonOperator(
    task_id="kafka_health_check",
    python_callable=check_kafka_health,
    dag=dag
)

debezium_health_check = PythonOperator(
    task_id="debezium_health_check",
    python_callable=check_debezium_connectors,
    dag=dag
)

setup_connectors = PythonOperator(
    task_id="setup_debezium_connectors",
    python_callable=setup_debezium_connectors,
    dag=dag
)

start_cdc_processor = GlueJobOperator(
    task_id="start_cdc_processor",
    job_name="cdc-pipeline-dev-cdc-processor",
    script_location=f"s3://{S3_BUCKET}/scripts/cdc_processor.py",
    s3_bucket=S3_BUCKET,
    iam_role_name=GLUE_ROLE_NAME,
    dag=dag
)

monitor_cdc_processor = GlueJobSensor(
    task_id="monitor_cdc_processor",
    job_name="cdc-pipeline-dev-cdc-processor",
    run_id="{{ task_instance.xcom_pull(task_ids='start_cdc_processor', key='return_value') }}",
    dag=dag
)

data_quality_check = PythonOperator(
    task_id="data_quality_monitoring",
    python_callable=monitor_data_quality,
    dag=dag
)

generate_gold_layer = GlueJobOperator(
    task_id="generate_gold_layer",
    job_name="cdc-pipeline-dev-gold-processor",
    script_location=f"s3://{S3_BUCKET}/scripts/gold_processor.py",
    s3_bucket=S3_BUCKET,
    iam_role_name=GLUE_ROLE_NAME,
    dag=dag
)

monitor_gold_processor = GlueJobSensor(
    task_id="monitor_gold_processor",
    job_name="cdc-pipeline-dev-gold-processor",
    run_id="{{ task_instance.xcom_pull(task_ids='generate_gold_layer', key='return_value') }}",
    dag=dag
)

success_notification = SnsPublishOperator(
    task_id="success_notification",
    target_arn=f"arn:aws:sns:{AWS_REGION}:123456789012:cdc-pipeline-dev-alerts",
    message="CDC Pipeline completed successfully",
    subject="CDC Pipeline Success",
    dag=dag,
    trigger_rule=TriggerRule.ALL_SUCCESS
)

failure_notification = SnsPublishOperator(
    task_id="failure_notification",
    target_arn=f"arn:aws:sns:{AWS_REGION}:123456789012:cdc-pipeline-dev-alerts",
    message="CDC Pipeline failed. Check Airflow logs.",
    subject="CDC Pipeline Failure",
    dag=dag,
    trigger_rule=TriggerRule.ONE_FAILED
)

cleanup_failed = PythonOperator(
    task_id="cleanup_failed_runs",
    python_callable=cleanup_failed_runs,
    dag=dag,
    trigger_rule=TriggerRule.ONE_FAILED
)


kafka_health_check >> debezium_health_check >> setup_connectors
setup_connectors >> start_cdc_processor >> monitor_cdc_processor
monitor_cdc_processor >> data_quality_check >> generate_gold_layer
generate_gold_layer >> monitor_gold_processor >> success_notification

[
    kafka_health_check, debezium_health_check, setup_connectors,
    start_cdc_processor, monitor_cdc_processor,
    data_quality_check, generate_gold_layer, monitor_gold_processor
] >> failure_notification >> cleanup_failed
