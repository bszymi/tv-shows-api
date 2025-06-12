# AWS Deployment Guide

This document outlines the recommended AWS architecture and deployment strategy for the TV Shows API.

## Architecture Overview

### Recommended AWS Services

1. **Compute**: AWS ECS with Fargate
2. **Database**: Amazon RDS PostgreSQL
3. **Cache/Queue**: Amazon ElastiCache Redis
4. **Load Balancer**: Application Load Balancer (ALB)
5. **Container Registry**: Amazon ECR
6. **CI/CD**: GitHub Actions + AWS CodeDeploy
7. **Monitoring**: CloudWatch + AWS X-Ray
8. **Secrets**: AWS Secrets Manager
9. **Storage**: S3 for static assets (if needed)

### Architecture Diagram

```
Internet → ALB → ECS Fargate Cluster
                     ↓
                 RDS PostgreSQL
                     ↓
                 ElastiCache Redis
```

## Deployment Options

### Option 1: ECS with Fargate (Recommended)

**Pros:**
- Serverless containers, no EC2 management
- Automatic scaling
- Pay-per-use pricing
- Built-in load balancing
- Easy rollbacks

**Resources:**
- ECS Cluster with Fargate capacity provider
- ECS Service with 2+ tasks for high availability
- Task Definition with web and worker containers
- ALB with target groups

### Option 2: Elastic Beanstalk

**Pros:**
- Simplified deployment process
- Automatic capacity provisioning
- Health monitoring
- Easy environment management

**Cons:**
- Less control over infrastructure
- Limited customization options

## Infrastructure Setup

### 1. VPC and Networking

```yaml
# VPC Configuration
VPC:
  CIDR: 10.0.0.0/16
  
Public Subnets:
  - 10.0.1.0/24 (AZ-a)
  - 10.0.2.0/24 (AZ-b)
  
Private Subnets:
  - 10.0.10.0/24 (AZ-a)
  - 10.0.20.0/24 (AZ-b)
  
Database Subnets:
  - 10.0.100.0/24 (AZ-a)
  - 10.0.200.0/24 (AZ-b)
```

### 2. RDS PostgreSQL Setup

```yaml
Engine: PostgreSQL 16
Instance Class: db.t3.micro (development) / db.r5.large (production)
Multi-AZ: Yes (production)
Storage: gp3, 100GB initial
Backup Retention: 7 days
Encryption: Yes
Parameter Group: Custom with optimized settings
```

**Recommended Parameters:**
- `shared_preload_libraries = 'pg_stat_statements'`
- `log_statement = 'all'` (development only)
- `max_connections = 200`

### 3. ElastiCache Redis Setup

```yaml
Engine: Redis 7.x
Node Type: cache.t3.micro (development) / cache.r6g.large (production)
Cluster Mode: Disabled
Multi-AZ: Yes (production)
Backup: Daily snapshots
Encryption: In-transit and at-rest
```

### 4. ECS Configuration

#### Task Definition (JSON)

```json
{
  "family": "tv-shows-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "web",
      "image": "ACCOUNT.dkr.ecr.REGION.amazonaws.com/tv-shows-api:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "RAILS_ENV",
          "value": "production"
        },
        {
          "name": "RAILS_LOG_TO_STDOUT",
          "value": "true"
        }
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:tv-shows-api/database-url"
        },
        {
          "name": "REDIS_URL",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:tv-shows-api/redis-url"
        },
        {
          "name": "RAILS_MASTER_KEY",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:tv-shows-api/rails-master-key"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/tv-shows-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "web"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/up || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3
      }
    },
    {
      "name": "sidekiq",
      "image": "ACCOUNT.dkr.ecr.REGION.amazonaws.com/tv-shows-api:latest",
      "command": ["bundle", "exec", "sidekiq"],
      "environment": [
        {
          "name": "RAILS_ENV",
          "value": "production"
        }
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:tv-shows-api/database-url"
        },
        {
          "name": "REDIS_URL",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:tv-shows-api/redis-url"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/tv-shows-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "sidekiq"
        }
      }
    }
  ]
}
```

### 5. Application Load Balancer

```yaml
Type: Application Load Balancer
Scheme: Internet-facing
Subnets: Public subnets in multiple AZs
Security Groups: Allow HTTP/HTTPS inbound

Target Groups:
  - Name: tv-shows-api-web
    Protocol: HTTP
    Port: 3000
    Health Check Path: /up
    Health Check Interval: 30s
    Health Check Timeout: 5s
    Healthy Threshold: 2
    Unhealthy Threshold: 3

Listeners:
  - Port: 80 (redirect to 443)
  - Port: 443 (forward to target group)
```

## Environment Configuration

### Environment Variables

```bash
# Application
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# Database
DATABASE_URL=postgresql://username:password@rds-endpoint:5432/database_name

# Redis
REDIS_URL=redis://elasticache-endpoint:6379/0

# Security
RAILS_MASTER_KEY=your_master_key_here

# Monitoring (optional)
NEW_RELIC_LICENSE_KEY=your_key_here
DATADOG_API_KEY=your_key_here
```

### AWS Secrets Manager

Store sensitive configuration in AWS Secrets Manager:

```bash
# Database URL
aws secretsmanager create-secret \
  --name "tv-shows-api/database-url" \
  --description "Database connection URL" \
  --secret-string "postgresql://username:password@endpoint:5432/dbname"

# Redis URL
aws secretsmanager create-secret \
  --name "tv-shows-api/redis-url" \
  --description "Redis connection URL" \
  --secret-string "redis://endpoint:6379/0"

# Rails Master Key
aws secretsmanager create-secret \
  --name "tv-shows-api/rails-master-key" \
  --description "Rails master key for credentials" \
  --secret-string "your_master_key_here"
```

## Deployment Process

### 1. ECR Repository Setup

```bash
# Create ECR repository
aws ecr create-repository --repository-name tv-shows-api

# Get login token
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Build and push image
docker build -t tv-shows-api .
docker tag tv-shows-api:latest ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/tv-shows-api:latest
docker push ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/tv-shows-api:latest
```

### 2. Database Migration

```bash
# Run migrations (one-time task)
aws ecs run-task \
  --cluster tv-shows-api-cluster \
  --task-definition tv-shows-api-migration:1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345],securityGroups=[sg-12345],assignPublicIp=ENABLED}"
```

### 3. Service Deployment

```bash
# Create ECS service
aws ecs create-service \
  --cluster tv-shows-api-cluster \
  --service-name tv-shows-api-web \
  --task-definition tv-shows-api:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345,subnet-67890],securityGroups=[sg-12345],assignPublicIp=DISABLED}" \
  --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:region:account:targetgroup/tv-shows-api-web/1234567890,containerName=web,containerPort=3000
```

## Monitoring and Logging

### CloudWatch Configuration

```yaml
Log Groups:
  - /ecs/tv-shows-api
  - /aws/rds/instance/tv-shows-api-db/postgresql

Metrics:
  - ECS Service CPU/Memory utilization
  - RDS CPU/Memory utilization
  - ALB request count and latency
  - Custom application metrics

Alarms:
  - High CPU utilization (>80%)
  - High memory utilization (>80%)
  - Database connection errors
  - Application error rate (>5%)
```

### Custom Metrics

```ruby
# Add to application_controller.rb
class ApplicationController < ActionController::API
  around_action :measure_action

  private

  def measure_action
    start_time = Time.current
    yield
  ensure
    duration = (Time.current - start_time) * 1000
    CloudWatch.put_metric_data(
      namespace: 'TvShowsApi',
      metric_data: [
        {
          metric_name: 'ResponseTime',
          value: duration,
          unit: 'Milliseconds',
          dimensions: [
            {
              name: 'Controller',
              value: self.class.name
            },
            {
              name: 'Action', 
              value: action_name
            }
          ]
        }
      ]
    )
  end
end
```

## Security Considerations

### Network Security

1. **VPC**: Deploy in private subnets
2. **Security Groups**: Minimal required ports
3. **NACLs**: Additional layer of defense
4. **WAF**: Protect against common attacks

### Application Security

1. **Secrets Management**: Use AWS Secrets Manager
2. **Encryption**: Enable at-rest and in-transit
3. **IAM Roles**: Principle of least privilege
4. **Authentication**: Implement API authentication

### Security Groups

```yaml
ECS Security Group:
  Inbound:
    - Port 3000 from ALB Security Group
  Outbound:
    - Port 443 to 0.0.0.0/0 (HTTPS)
    - Port 5432 to RDS Security Group
    - Port 6379 to ElastiCache Security Group

RDS Security Group:
  Inbound:
    - Port 5432 from ECS Security Group
  Outbound: None

ElastiCache Security Group:
  Inbound:
    - Port 6379 from ECS Security Group
  Outbound: None

ALB Security Group:
  Inbound:
    - Port 80 from 0.0.0.0/0
    - Port 443 from 0.0.0.0/0
  Outbound:
    - Port 3000 to ECS Security Group
```

## Cost Optimization

### Development Environment

- **ECS**: 1 task, t4g.nano instances
- **RDS**: db.t3.micro, single-AZ
- **ElastiCache**: cache.t3.micro
- **Estimated Cost**: ~$50-80/month

### Production Environment

- **ECS**: 2+ tasks, auto-scaling
- **RDS**: db.r5.large, multi-AZ
- **ElastiCache**: cache.r6g.large
- **Estimated Cost**: ~$300-500/month

### Cost Optimization Tips

1. Use Reserved Instances for predictable workloads
2. Enable RDS storage auto-scaling
3. Use ECS auto-scaling based on CPU/memory
4. Implement CloudWatch alarms for cost monitoring
5. Use S3 lifecycle policies for log retention

## Disaster Recovery

### Backup Strategy

1. **RDS**: Automated backups + manual snapshots
2. **ElastiCache**: Daily snapshots
3. **Application**: Immutable container images
4. **Secrets**: Cross-region replication

### Recovery Procedures

1. **Database Recovery**: Point-in-time restore
2. **Full Stack Recovery**: Infrastructure as Code
3. **Blue/Green Deployment**: Zero-downtime deployments
4. **Multi-Region**: Active-passive setup

## Scaling Considerations

### Horizontal Scaling

```yaml
ECS Auto Scaling:
  Target CPU: 70%
  Min Capacity: 2
  Max Capacity: 10
  Scale Out Cooldown: 300s
  Scale In Cooldown: 300s

RDS Read Replicas:
  Count: 1-3 based on read load
  Instance Class: Same as primary
  Regions: Same or cross-region
```

### Vertical Scaling

- Monitor CloudWatch metrics
- Upgrade instance classes as needed
- Test scaling changes in staging first

This deployment guide provides a production-ready architecture that can scale from small development environments to large-scale production deployments.