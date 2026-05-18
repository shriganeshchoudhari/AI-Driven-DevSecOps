variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project/Platform name"
  type        = string
  default     = "aiops-platform"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "database_subnets" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
}

variable "intra_subnets" {
  description = "CIDR blocks for intra subnets"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Enable public EKS endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private EKS endpoint"
  type        = bool
  default     = true
}

variable "node_group_instance_types" {
  description = "EC2 instance types for node group"
  type        = list(string)
}

variable "node_group_desired_size" {
  description = "Desired number of nodes"
  type        = number
}

variable "node_group_min_size" {
  description = "Minimum number of nodes"
  type        = number
}

variable "node_group_max_size" {
  description = "Maximum number of nodes"
  type        = number
}

variable "node_group_disk_size" {
  description = "Disk size in GB for nodes"
  type        = number
  default     = 50
}

variable "enable_karpenter" {
  description = "Enable Karpenter"
  type        = bool
  default     = false
}

variable "karpenter_instance_families" {
  description = "Karpenter instance families"
  type        = list(string)
  default     = []
}

variable "enable_aws_load_balancer_controller" {
  description = "Deploy AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Deploy ExternalDNS"
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
  description = "Deploy EBS CSI Driver resizer"
  type        = bool
  default     = true
}

variable "enable_efs_csi_driver" {
  description = "Deploy EFS CSI Driver"
  type        = bool
  default     = false
}

variable "ebs_encryption_enabled" {
  description = "Enable EBS encryption"
  type        = bool
  default     = true
}

variable "ebs_kms_key_arn" {
  description = "ARN of KMS key for EBS"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "rds_instance_class" {
  description = "RDS instance type"
  type        = string
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
}

variable "rds_engine" {
  description = "RDS database engine"
  type        = string
}

variable "rds_engine_version" {
  description = "RDS engine version"
  type        = string
}

variable "rds_database_name" {
  description = "RDS database name"
  type        = string
}

variable "rds_username" {
  description = "RDS master username"
  type        = string
  sensitive   = true
}

variable "rds_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "elasticache_node_type" {
  description = "ElastiCache node type"
  type        = string
}

variable "elasticache_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
}

variable "elasticache_engine_version" {
  description = "Redis engine version"
  type        = string
}

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging"
  type        = bool
  default     = true
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "domain_name" {
  description = "Domain name for Route53"
  type        = string
  default     = ""
}

variable "enable_route53" {
  description = "Create Route53 hosted zones"
  type        = bool
  default     = false
}

variable "backup_bucket_name" {
  description = "Backup S3 bucket name"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 14
}

variable "enable_waf" {
  description = "Enable WAF"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "WAF rate limit"
  type        = number
  default     = 2000
}

variable "ecr_repository_names" {
  description = "List of ECR repository names"
  type        = list(string)
  default     = ["api-gateway", "user-service"]
}
