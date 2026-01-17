#!/bin/bash
# CDC Pipeline - AWS Deployment Script
# Deploys the complete CDC pipeline to AWS using Terraform

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 CDC Pipeline - AWS Deployment${NC}"
echo "========================================"
echo ""

# Project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Terraform is not installed. Please install Terraform first.${NC}"
        echo "  brew install terraform  # macOS"
        echo "  wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip"
        exit 1
    fi
    echo "✅ Terraform: $(terraform version)"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed. Please install AWS CLI first.${NC}"
        exit 1
    fi
    echo "✅ AWS CLI: $(aws --version)"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}AWS credentials not configured. Run 'aws configure' first.${NC}"
        exit 1
    fi
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "✅ AWS Account: $AWS_ACCOUNT_ID"
    
    echo ""
}

# Function to initialize Terraform
init_terraform() {
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    cd terraform
    terraform init
    echo ""
}

# Function to plan deployment
plan_deployment() {
    echo -e "${YELLOW}Planning deployment...${NC}"
    terraform plan \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${ENVIRONMENT}" \
        -var="aws_region=${AWS_REGION}" \
        -var="alert_email=${ALERT_EMAIL}"
    echo ""
}

# Function to deploy
deploy() {
    echo -e "${YELLOW}Deploying infrastructure...${NC}"
    terraform apply \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${ENVIRONMENT}" \
        -var="aws_region=${AWS_REGION}" \
        -var="alert_email=${ALERT_EMAIL}" \
        -auto-approve
    echo ""
}

# Function to upload scripts
upload_scripts() {
    echo -e "${YELLOW}Uploading Glue scripts to S3...${NC}"
    
    S3_BUCKET=$(terraform output -raw s3_data_lake_bucket)
    
    # Upload Glue scripts
    aws s3 cp glue/ s3://${S3_BUCKET}/scripts/ --recursive
    echo "✅ Uploaded glue scripts to s3://${S3_BUCKET}/scripts/"
    
    # Upload Airflow DAGs
    aws s3 cp airflow/dags/ s3://${S3_BUCKET}/dags/ --recursive
    echo "✅ Uploaded airflow dags to s3://${S3_BUCKET}/dags/"
    
    echo ""
}

# Function to setup connector
setup_connector() {
    echo -e "${YELLOW}Setting up Debezium connector...${NC}"
    
    DEBEZIUM_URL=$(terraform output -raw debezium_connect_url)
    RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
    DB_USER=$(grep 'db_username' variables.tf | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    DB_PASS=$(grep 'db_password' variables.tf | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    DB_NAME=$(grep 'db_name' variables.tf | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    
    curl -X PUT "${DEBEZIUM_URL}/connectors/cdc-connector/config" \
        -H "Content-Type: application/json" \
        -d '{
            "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
            "database.hostname": "'${RDS_ENDPOINT}'",
            "database.port": "5432",
            "database.user": "'${DB_USER}'",
            "database.password": "'${DB_PASS}'",
            "database.dbname": "'${DB_NAME}'",
            "database.server.name": "cdc-server",
            "topic.prefix": "cdc",
            "table.include.list": "public.users,public.products,public.orders",
            "plugin.name": "pgoutput",
            "key.converter": "org.apache.kafka.connect.json.JsonConverter",
            "value.converter": "org.apache.kafka.connect.json.JsonConverter",
            "transforms": "unwrap",
            "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
        }'
    
    echo ""
    echo "✅ Connector setup initiated"
}

# Function to start Glue jobs
start_glue_jobs() {
    echo -e "${YELLOW}Starting Glue jobs...${NC}"
    
    PROJECT_NAME=$(grep 'project_name' terraform/variables.tf | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    ENVIRONMENT=$(grep 'environment' terraform/variables.tf | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    
    # Start CDC Processor
    aws glue start-job-run \
        --job-name ${PROJECT_NAME}-${ENVIRONMENT}-cdc-processor \
        --region ${AWS_REGION}
    echo "✅ Started CDC Processor job"
    
    # Start Gold Processor
    aws glue start-job-run \
        --job-name ${PROJECT_NAME}-${ENVIRONMENT}-gold-processor \
        --region ${AWS_REGION}
    echo "✅ Started Gold Processor job"
    
    echo ""
}

# Function to show status
show_status() {
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo ""
    echo "Infrastructure Status:"
    terraform output
    
    echo ""
    echo "Next Steps:"
    echo "1. Access Airflow UI: $(terraform output -raw airflow_url)"
    echo "2. Check Debezium connectors: $(terraform output -raw debezium_connect_url)/connectors"
    echo "3. Query data in Athena using the Glue Data Catalog"
    echo ""
    echo "Useful Commands:"
    echo "  # View logs"
    echo "  aws logs tail /aws/glue/${PROJECT_NAME}-${ENVIRONMENT} --follow"
    echo ""
    echo "  # Stop Glue jobs"
    echo "  aws glue stop-job-run --job-run-id \$(aws glue get-job-runs --job-name ${PROJECT_NAME}-${ENVIRONMENT}-cdc-processor --query 'JobRuns[0].Id' --output text)"
    echo ""
    echo "  # Destroy infrastructure"
    echo "  cd terraform && terraform destroy -auto-approve"
}

# Main configuration
PROJECT_NAME="${1:-cdc-pipeline}"
ENVIRONMENT="${2:-dev}"
AWS_REGION="${3:-ap-south-1}"
ALERT_EMAIL="${4:-alerts@example.com}"

echo "Configuration:"
echo "  Project: ${PROJECT_NAME}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Region: ${AWS_REGION}"
echo "  Alert Email: ${ALERT_EMAIL}"
echo ""

# Handle commands
case "${5:-deploy}" in
    plan)
        check_prerequisites
        init_terraform
        plan_deployment
        ;;
    deploy)
        check_prerequisites
        init_terraform
        deploy
        upload_scripts
        setup_connector
        start_glue_jobs
        show_status
        ;;
    scripts)
        upload_scripts
        ;;
    connector)
        setup_connector
        ;;
    glue)
        start_glue_jobs
        ;;
    status)
        show_status
        ;;
    destroy)
        echo -e "${YELLOW}Destroying infrastructure...${NC}"
        cd terraform
        terraform destroy -var="project_name=${PROJECT_NAME}" -var="environment=${ENVIRONMENT}" -auto-approve
        echo "✅ Infrastructure destroyed"
        ;;
    help|--help|-h)
        echo "Usage: ./deploy.sh [project_name] [environment] [region] [email] [command]"
        echo ""
        echo "Commands:"
        echo "  plan       - Plan deployment without applying"
        echo "  deploy     - Full deployment (default)"
        echo "  scripts    - Upload Glue scripts only"
        echo "  connector  - Setup Debezium connector only"
        echo "  glue       - Start Glue jobs only"
        echo "  status     - Show deployment status"
        echo "  destroy    - Destroy all infrastructure"
        echo "  help       - Show this help"
        echo ""
        echo "Examples:"
        echo "  ./deploy.sh                          # Default deployment"
        echo "  ./deploy.sh my-project prod us-east-1 my@email.com plan"
        echo "  ./deploy.sh cdc-pipeline dev ap-south-1 alerts@example.com destroy"
        ;;
    *)
        echo "Unknown command: $5"
        ./deploy.sh help
        exit 1
        ;;
esac

