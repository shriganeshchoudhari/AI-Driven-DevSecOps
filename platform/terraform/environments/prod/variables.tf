variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project/Platform name used for resource naming"
  type        = string
  default     = "aiops-platform"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for multi-AZ deployment"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "database_subnets" {
  description = "CIDR blocks for database subnets (one per AZ)"
  type        = list(string)
}

variable "intra_subnets" {
  description = "CIDR blocks for intra-cluster subnets (one per AZ, no NAT)"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the EKS cluster endpoint"
  type        = bool
  default     = false
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "node_group_instance_types" {
  description = "List of EC2 instance types for the EKS managed node group"
  type        = list(string)
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
}

variable "node_group_disk_size" {
  description = "Disk size in GB for node group instances"
  type        = number
  default     = 100
}

variable "enable_karpenter" {
  description = "Enable Karpenter for node auto-provisioning"
  type        = bool
  default     = false
}

variable "karpenter_instance_families" {
  description = "List of EC2 instance families allowed by Karpenter"
  type        = list(string)
  default     = []
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

variable "oidc_provider_enabled" {
  description = "Enable OIDC identity provider for the cluster"
  type        = bool
  default     = true
}

variable "kms_key_administrators" {
  description = "List of IAM ARNs for KMS key administrators"
  type        = list(string)
  default     = []
}

variable "kms_key_users" {
  description = "List of IAM ARNs for KMS key users"
  type        = list(string)
  default     = []
}

variable "enable_aws_load_balancer_controller" {
  description = "Deploy AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Deploy ExternalDNS for Route53 integration"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Deploy Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Deploy Metrics Server"
  type        = bool
  default     = true
}

variable "enable_secrets_store_csi_driver" {
  description = "Deploy Secrets Store CSI Driver"
  type        = bool
  default     = true
}

variable "enable_ebs_csi_resizer" {
  description = "Deploy EBS CSI Driver resizer sidecar"
  type        = bool
  default     = true
}

variable "enable_efs_csi_driver" {
  description = "Deploy EFS CSI Driver"
  type        = bool
  default     = false
}

variable "ebs_encryption_enabled" {
  description = "Enable EBS volume encryption by default"
  type        = bool
  default     = true
}

variable "ebs_kms_key_arn" {
  description = "ARN of KMS key for EBS encryption (defaults to AWS managed)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "rds_instance_class" {
  description = "RDS instance type"
  type        = string
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
}

variable "rds_engine" {
  description = "RDS database engine"
  type        = string
}

variable "rds_engine_version" {
  description = "RDS database engine version"
  type        = string
}

variable "rds_database_name" {
  description = "Name of the RDS database"
  type        = string
}

variable "rds_username" {
  description = "Master username for RDS"
  type        = string
  sensitive   = true
}

variable "rds_password" {
  description = "Master password for RDS (leave empty to auto-generate)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "elasticache_node_type" {
  description = "ElastiCache node type"
  type        = string
}

variable "elasticache_num_cache_nodes" {
  description = "Number of ElastiCache cache nodes"
  type        = number
}

variable "elasticache_engine_version" {
  description = "ElastiCache Redis engine version"
  type        = string
}

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging for all services"
  type        = bool
  default     = true
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 365
}

variable "domain_name" {
  description = "Domain name for Route53 hosted zones"
  type        = string
  default     = ""
}

variable "enable_route53" {
  description = "Create Route53 private and public hosted zones"
  type        = bool
  default     = false
}

variable "backup_bucket_name" {
  description = "Name of the S3 backup bucket"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Retention period in days for backups"
  type        = number
  default     = 90
}

variable "enable_waf" {
  description = "Enable AWS WAF for ALB"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF rate-based rule (requests per 5-min)"
  type        = number
  default     = 2000
}

variable "ecr_repository_names" {
  description = "List of ECR repository names for microservices"
  type        = list(string)
  default     = [
    "api-gateway",
    "user-service",
    "workflow-service",
    "model-service",
    "notification-service",
    "data-pipeline",
    "monitoring-service",
    "audit-service",
  ]
}
