#!/bin/bash
# CDC Pipeline - Local Development Setup Script
# Sets up and runs the entire CDC pipeline locally using Docker Compose

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 CDC Pipeline Local Development Setup${NC}"
echo "================================================"
echo ""

# Project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi
    echo "✅ Docker: $(docker --version)"
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}Docker Compose is not installed. Please install Docker Compose first.${NC}"
        exit 1
    fi
    echo "✅ Docker Compose: $(docker-compose --version)"
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        echo -e "${RED}Docker is not running. Please start Docker.${NC}"
        exit 1
    fi
    echo "✅ Docker is running"
    
    echo ""
}

# Function to start services
start_services() {
    echo -e "${YELLOW}Starting CDC Pipeline services...${NC}"
    echo ""
    
    # Build and start all services
    docker-compose up -d --build
    
    echo ""
    echo -e "${YELLOW}Waiting for services to be healthy...${NC}"
    
    # Wait for PostgreSQL
    echo "Waiting for PostgreSQL..."
    until docker exec cdc-postgres pg_isready -U postgres -d cdc_demo; do
        sleep 2
    done
    echo "✅ PostgreSQL is ready"
    
    # Wait for Kafka
    echo "Waiting for Kafka..."
    until docker exec cdc-kafka kafka-broker-api-versions --bootstrap-server localhost:9092 &>/dev/null; do
        sleep 5
    done
    echo "✅ Kafka is ready"
    
    # Wait for Debezium
    echo "Waiting for Debezium..."
    until curl -s http://localhost:8083/connectors &>/dev/null; do
        sleep 5
    done
    echo "✅ Debezium Connect is ready"
    
    echo ""
    echo -e "${GREEN}🎉 All services are up and running!${NC}"
    echo ""
}

# Function to check status
check_status() {
    echo -e "${YELLOW}Service Status:${NC}"
    echo ""
    docker-compose ps
    echo ""
}

# Function to view logs
view_logs() {
    SERVICE="${1:-all}"
    
    if [ "$SERVICE" = "all" ]; then
        docker-compose logs -f
    else
        docker-compose logs -f "$SERVICE"
    fi
}

# Function to stop services
stop_services() {
    echo -e "${YELLOW}Stopping CDC Pipeline services...${NC}"
    docker-compose down -v
    echo -e "${GREEN}✅ Services stopped${NC}"
}

# Function to setup connectors
setup_connectors() {
    echo -e "${YELLOW}Setting up Debezium connectors...${NC}"
    
    # Create PostgreSQL connector
    curl -X PUT "http://localhost:8083/connectors/cdc-connector/config" \
        -H "Content-Type: application/json" \
        -d '{
            "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
            "database.hostname": "postgres",
            "database.port": "5432",
            "database.user": "postgres",
            "database.password": "postgres",
            "database.dbname": "cdc_demo",
            "database.server.name": "cdc-server",
            "topic.prefix": "cdc",
            "table.include.list": "public.users,public.products,public.orders",
            "plugin.name": "pgoutput",
            "key.converter": "org.apache.kafka.connect.json.JsonConverter",
            "value.converter": "org.apache.kafka.connect.json.JsonConverter",
            "key.converter.schemas.enable": "false",
            "value.converter.schemas.enable": "false",
            "transforms": "unwrap",
            "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
        }'
    
    echo ""
    echo -e "${GREEN}✅ Connector created!${NC}"
}

# Function to list topics
list_topics() {
    echo -e "${YELLOW}Kafka Topics:${NC}"
    docker exec cdc-kafka kafka-topics --list --bootstrap-server localhost:9092
}

# Function to test CDC
test_cdc() {
    echo -e "${YELLOW}Testing CDC with sample operations...${NC}"
    
    # Generate unique email
    TEST_EMAIL="test$(date +%s)@example.com"
    
    # Insert
    echo "Inserting a new user..."
    docker exec cdc-postgres psql -U postgres -d cdc_demo -c \
        "INSERT INTO users (name, email) VALUES ('Test User', '${TEST_EMAIL}');"
    echo "✅ Inserted user with email: ${TEST_EMAIL}"
    
    # Update
    echo "Updating the user..."
    docker exec cdc-postgres psql -U postgres -d cdc_demo -c \
        "UPDATE users SET name = 'Updated User' WHERE email = '${TEST_EMAIL}';"
    echo "✅ Updated user"
    
    # Delete
    echo "Deleting the test user..."
    docker exec cdc-postgres psql -U postgres -d cdc_demo -c \
        "DELETE FROM users WHERE email = '${TEST_EMAIL}';"
    echo "✅ Deleted user"
    
    echo ""
    echo -e "${GREEN}✅ CDC test operations completed!${NC}"
    echo ""
    echo "Check CDC events in Kafka:"
    echo "  docker exec cdc-kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic cdc.public.users --from-beginning | head -20"
}

# Function to show help
show_help() {
    echo "Usage: ./run.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start         Start all services (default)"
    echo "  stop          Stop all services and remove volumes"
    echo "  status        Show service status"
    echo "  logs [svc]    View logs (optionally for specific service)"
    echo "  connectors    Setup Debezium connectors"
    echo "  topics        List Kafka topics"
    echo "  test          Run CDC test operations"
    echo "  restart       Restart all services"
    echo "  help          Show this help message"
    echo ""
    echo "Services:"
    echo "  PostgreSQL:   localhost:5432 (postgres/postgres)"
    echo "  Kafka:        localhost:9092"
    echo "  Debezium:     localhost:8083"
    echo ""
}

# Main command handling
case "${1:-start}" in
    start)
        check_prerequisites
        start_services
        check_status
        ;;
    stop)
        stop_services
        ;;
    status)
        check_status
        ;;
    logs)
        view_logs "${2:-all}"
        ;;
    connectors)
        setup_connectors
        ;;
    topics)
        list_topics
        ;;
    test)
        test_cdc
        ;;
    restart)
        stop_services
        sleep 2
        start_services
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac

