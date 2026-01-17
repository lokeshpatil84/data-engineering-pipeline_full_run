"""
Debezium Connector Setup Script
Registers CDC connectors for PostgreSQL source
"""

import json
import requests
import sys
import os
from typing import Dict, List, Optional


class DebeziumConnectorManager:
    """Manage Debezium connectors for CDC"""
    
    def __init__(self, connect_url: str = None):
        self.connect_url = connect_url or os.getenv(
            "DEBEZIUM_CONNECT_URL", 
            "http://localhost:8083"
        )
        self.session = requests.Session()
    
    def get_connectors(self) -> List[Dict]:
        """List all existing connectors"""
        try:
            response = self.session.get(
                f"{self.connect_url}/connectors",
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error fetching connectors: {e}")
            return []
    
    def get_connector_status(self, connector_name: str) -> Optional[Dict]:
        """Get status of a specific connector"""
        try:
            response = self.session.get(
                f"{self.connect_url}/connectors/{connector_name}/status",
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error fetching connector status: {e}")
            return None
    
    def create_postgresql_connector(
        self,
        connector_name: str,
        database_host: str,
        database_port: int,
        database_name: str,
        database_user: str,
        database_password: str,
        tables: List[str] = None,
        slot_name: str = "debezium_slot",
        publication_name: str = "debezium_publication"
    ) -> bool:
        """Create a PostgreSQL CDC connector"""
        
        tables = tables or ["users", "products", "orders"]
        
        connector_config = {
            "name": connector_name,
            "config": {
                "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                "database.hostname": database_host,
                "database.port": str(database_port),
                "database.user": database_user,
                "database.password": database_password,
                "database.dbname": database_name,
                "database.server.name": f"{connector_name}-server",
                "topic.prefix": "cdc",
                "table.include.list": ",".join([f"public.{t}" for t in tables]),
                "publication.autocreate.mode": "filtered",
                "slot.name": slot_name,
                "plugin.name": "pgoutput",
                "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "key.converter.schemas.enable": "false",
                "value.converter.schemas.enable": "false",
                "transforms": "unwrap",
                "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
                "transforms.unwrap.add.fields": "op,ts_ms,source.ts_ms",
                "transforms.unwrap.delete.handling.mode": "rewrite",
                "heartbeat.interval.ms": "5000",
                "schema.history.internal.kafka.bootstrap.servers": os.getenv(
                    "KAFKA_BOOTSTRAP_SERVERS", 
                    "localhost:9092"
                ),
                "schema.history.internal.kafka.topic": f"schema-changes.{connector_name}"
            }
        }
        
        try:
            print(f"Creating connector: {connector_name}")
            response = self.session.put(
                f"{self.connect_url}/connectors/{connector_name}/config",
                json=connector_config["config"],
                headers={"Content-Type": "application/json"},
                timeout=30
            )
            response.raise_for_status()
            
            print(f"Connector '{connector_name}' created successfully!")
            return True
            
        except requests.RequestException as e:
            print(f"Error creating connector: {e}")
            if hasattr(e, 'response') and e.response is not None:
                print(f"Response: {e.response.text}")
            return False
    
    def delete_connector(self, connector_name: str) -> bool:
        """Delete a connector"""
        try:
            response = self.session.delete(
                f"{self.connect_url}/connectors/{connector_name}",
                timeout=30
            )
            response.raise_for_status()
            print(f"Connector '{connector_name}' deleted successfully!")
            return True
        except requests.RequestException as e:
            print(f"Error deleting connector: {e}")
            return False
    
    def pause_connector(self, connector_name: str) -> bool:
        """Pause a connector"""
        try:
            response = self.session.put(
                f"{self.connect_url}/connectors/{connector_name}/pause",
                timeout=30
            )
            response.raise_for_status()
            print(f"Connector '{connector_name}' paused!")
            return True
        except requests.RequestException as e:
            print(f"Error pausing connector: {e}")
            return False
    
    def resume_connector(self, connector_name: str) -> bool:
        """Resume a paused connector"""
        try:
            response = self.session.put(
                f"{self.connect_url}/connectors/{connector_name}/resume",
                timeout=30
            )
            response.raise_for_status()
            print(f"Connector '{connector_name}' resumed!")
            return True
        except requests.RequestException as e:
            print(f"Error resuming connector: {e}")
            return False
    
    def restart_connector(self, connector_name: str) -> bool:
        """Restart a connector"""
        try:
            response = self.session.post(
                f"{self.connect_url}/connectors/{connector_name}/restart",
                timeout=30
            )
            response.raise_for_status()
            print(f"Connector '{connector_name}' restart initiated!")
            return True
        except requests.RequestException as e:
            print(f"Error restarting connector: {e}")
            return False
    
    def get_connector_topics(self, connector_name: str) -> List[str]:
        """Get topics created by a connector"""
        try:
            response = self.session.get(
                f"{self.connect_url}/connectors/{connector_name}/topics",
                timeout=10
            )
            response.raise_for_status()
            return response.json().get("topics", [])
        except requests.RequestException as e:
            print(f"Error fetching topics: {e}")
            return []


def setup_connectors_local():
    """Setup connectors for local development"""
    manager = DebeziumConnectorManager()
    
    # Check existing connectors
    existing = manager.get_connectors()
    print(f"Existing connectors: {existing}")
    
    # Create connector for demo database
    success = manager.create_postgresql_connector(
        connector_name="cdc-connector",
        database_host=os.getenv("DB_HOST", "localhost"),
        database_port=int(os.getenv("DB_PORT", "5432")),
        database_name=os.getenv("DB_NAME", "cdc_demo"),
        database_user=os.getenv("DB_USER", "postgres"),
        database_password=os.getenv("DB_PASSWORD", "postgres"),
        tables=["users", "products", "orders"]
    )
    
    if success:
        # Wait a moment and check status
        import time
        time.sleep(5)
        status = manager.get_connector_status("cdc-connector")
        print(f"Connector status: {json.dumps(status, indent=2)}")
        
        # Get topics
        topics = manager.get_connector_topics("cdc-connector")
        print(f"Topics created: {topics}")


def setup_connectors_aws(connect_url: str):
    """Setup connectors for AWS deployment"""
    manager = DebeziumConnectorManager(connect_url)
    
    # Get database credentials from Secrets Manager
    import boto3
    secrets_client = boto3.client('secretsmanager')
    
    secret_name = os.getenv("DB_SECRET_NAME", "cdc-pipeline-dev-db-credentials")
    
    try:
        secret = secrets_client.get_secret_value(SecretId=secret_name)
        credentials = json.loads(secret['SecretString'])
    except Exception as e:
        print(f"Error fetching secret: {e}")
        return
    
    # Create connector
    success = manager.create_postgresql_connector(
        connector_name="cdc-connector",
        database_host=credentials['host'],
        database_port=int(credentials['port']),
        database_name=credentials['database'],
        database_user=credentials['username'],
        database_password=credentials['password'],
        tables=["users", "products", "orders"]
    )


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Debezium Connector Manager")
    parser.add_argument("--local", action="store_true", help="Setup for local development")
    parser.add_argument("--aws", action="store_true", help="Setup for AWS deployment")
    parser.add_argument("--url", type=str, help="Connect URL for AWS")
    parser.add_argument("--list", action="store_true", help="List existing connectors")
    parser.add_argument("--status", type=str, help="Check connector status")
    parser.add_argument("--delete", type=str, help="Delete a connector")
    parser.add_argument("--restart", type=str, help="Restart a connector")
    
    args = parser.parse_args()
    
    if args.local:
        setup_connectors_local()
    elif args.aws:
        if not args.url:
            print("Error: --url required for AWS setup")
            sys.exit(1)
        setup_connectors_aws(args.url)
    elif args.list:
        manager = DebeziumConnectorManager()
        connectors = manager.get_connectors()
        print(f"Connectors: {json.dumps(connectors, indent=2)}")
    elif args.status:
        manager = DebeziumConnectorManager()
        status = manager.get_connector_status(args.status)
        print(f"Status: {json.dumps(status, indent=2)}")
    elif args.delete:
        manager = DebeziumConnectorManager()
        manager.delete_connector(args.delete)
    elif args.restart:
        manager = DebeziumConnectorManager()
        manager.restart_connector(args.restart)
    else:
        parser.print_help()

