#!/bin/bash

# TV Shows API Deployment Script
# This script demonstrates how to deploy the application to AWS ECS

set -e

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"tv-shows-api-cluster"}
SERVICE_NAME=${SERVICE_NAME:-"tv-shows-api-web"}
TASK_DEFINITION=${TASK_DEFINITION:-"tv-shows-api"}
ECR_REPOSITORY=${ECR_REPOSITORY:-"tv-shows-api"}
AWS_REGION=${AWS_REGION:-"us-east-1"}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
check_requirements() {
    log_info "Checking deployment requirements..."
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS_ACCOUNT_ID environment variable is required"
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    log_info "Requirements check passed"
}

# Build and push Docker image
build_and_push() {
    local image_tag=$1
    local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
    
    log_info "Building Docker image..."
    docker build -t ${ECR_REPOSITORY}:${image_tag} .
    
    log_info "Tagging image for ECR..."
    docker tag ${ECR_REPOSITORY}:${image_tag} ${ecr_uri}:${image_tag}
    docker tag ${ECR_REPOSITORY}:${image_tag} ${ecr_uri}:latest
    
    log_info "Logging into ECR..."
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ecr_uri}
    
    log_info "Pushing image to ECR..."
    docker push ${ecr_uri}:${image_tag}
    docker push ${ecr_uri}:latest
    
    echo ${ecr_uri}:${image_tag}
}

# Run database migrations
run_migrations() {
    local image_uri=$1
    
    log_info "Running database migrations..."
    
    # Create a one-time task for migrations
    local task_definition=$(cat <<EOF
{
  "family": "${TASK_DEFINITION}-migration",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "migration",
      "image": "${image_uri}",
      "command": ["bundle", "exec", "rails", "db:migrate"],
      "environment": [
        {
          "name": "RAILS_ENV",
          "value": "production"
        }
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tv-shows-api/database-url"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/tv-shows-api-migrations",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "migration"
        }
      }
    }
  ]
}
EOF
    )
    
    # Register the migration task definition
    local revision=$(echo "$task_definition" | aws ecs register-task-definition \
        --cli-input-json file:///dev/stdin \
        --query 'taskDefinition.revision' \
        --output text)
    
    log_info "Registered migration task definition revision: ${revision}"
    
    # Run the migration task
    local task_arn=$(aws ecs run-task \
        --cluster ${CLUSTER_NAME} \
        --task-definition ${TASK_DEFINITION}-migration:${revision} \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[subnet-12345],securityGroups=[sg-12345],assignPublicIp=ENABLED}" \
        --query 'tasks[0].taskArn' \
        --output text)
    
    log_info "Started migration task: ${task_arn}"
    
    # Wait for migration to complete
    log_info "Waiting for migration to complete..."
    aws ecs wait tasks-stopped --cluster ${CLUSTER_NAME} --tasks ${task_arn}
    
    # Check if migration was successful
    local exit_code=$(aws ecs describe-tasks \
        --cluster ${CLUSTER_NAME} \
        --tasks ${task_arn} \
        --query 'tasks[0].containers[0].exitCode' \
        --output text)
    
    if [ "$exit_code" != "0" ]; then
        log_error "Migration failed with exit code: ${exit_code}"
        exit 1
    fi
    
    log_info "Migration completed successfully"
}

# Update ECS service
update_service() {
    local image_uri=$1
    
    log_info "Updating ECS service..."
    
    # Get current task definition
    local current_task_def=$(aws ecs describe-task-definition \
        --task-definition ${TASK_DEFINITION} \
        --query 'taskDefinition')
    
    # Update image URI in task definition
    local updated_task_def=$(echo "$current_task_def" | jq --arg image "$image_uri" \
        '.containerDefinitions[0].image = $image | 
         del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)')
    
    # Register new task definition
    local revision=$(echo "$updated_task_def" | aws ecs register-task-definition \
        --cli-input-json file:///dev/stdin \
        --query 'taskDefinition.revision' \
        --output text)
    
    log_info "Registered new task definition revision: ${revision}"
    
    # Update the service
    aws ecs update-service \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --task-definition ${TASK_DEFINITION}:${revision} \
        --force-new-deployment > /dev/null
    
    log_info "Service update initiated"
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME}
    
    log_info "Deployment completed successfully"
}

# Health check
health_check() {
    local alb_dns=$1
    local max_attempts=30
    local attempt=1
    
    log_info "Performing health check..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "http://${alb_dns}/up" > /dev/null 2>&1; then
            log_info "Health check passed"
            return 0
        fi
        
        log_info "Health check attempt ${attempt}/${max_attempts} failed, retrying..."
        sleep 10
        ((attempt++))
    done
    
    log_error "Health check failed after ${max_attempts} attempts"
    return 1
}

# Main deployment function
deploy() {
    local environment=${1:-staging}
    local image_tag=${2:-$(git rev-parse --short HEAD)}
    
    log_info "Starting deployment to ${environment} environment"
    log_info "Image tag: ${image_tag}"
    
    # Check requirements
    check_requirements
    
    # Build and push image
    local image_uri=$(build_and_push $image_tag)
    log_info "Image URI: ${image_uri}"
    
    # Run migrations
    run_migrations $image_uri
    
    # Update service
    update_service $image_uri
    
    # Health check (would need ALB DNS name)
    # health_check "your-alb-dns-name.us-east-1.elb.amazonaws.com"
    
    log_info "Deployment to ${environment} completed successfully!"
}

# Rollback function
rollback() {
    local target_revision=${1}
    
    if [ -z "$target_revision" ]; then
        log_error "Target revision is required for rollback"
        exit 1
    fi
    
    log_info "Rolling back to revision ${target_revision}"
    
    aws ecs update-service \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --task-definition ${TASK_DEFINITION}:${target_revision} \
        --force-new-deployment > /dev/null
    
    log_info "Rollback initiated"
    
    # Wait for rollback to complete
    log_info "Waiting for rollback to complete..."
    aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME}
    
    log_info "Rollback completed successfully"
}

# Script usage
usage() {
    echo "Usage: $0 [deploy|rollback] [environment] [image_tag|revision]"
    echo ""
    echo "Commands:"
    echo "  deploy [environment] [image_tag]  - Deploy application (default: staging, current git hash)"
    echo "  rollback [revision]               - Rollback to specific task definition revision"
    echo ""
    echo "Examples:"
    echo "  $0 deploy staging v1.0.0"
    echo "  $0 deploy production"
    echo "  $0 rollback 123"
}

# Main script execution
case "${1:-deploy}" in
    deploy)
        deploy $2 $3
        ;;
    rollback)
        rollback $2
        ;;
    *)
        usage
        exit 1
        ;;
esac