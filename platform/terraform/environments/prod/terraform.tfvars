aws_region          = "us-west-2"
environment         = "prod"
project_name        = "aiops-platform"

vpc_cidr            = "10.64.0.0/16"
availability_zones  = ["us-west-2a", "us-west-2b", "us-west-2c"]
private_subnets     = ["10.64.0.0/19", "10.64.32.0/19", "10.64.64.0/19"]
public_subnets      = ["10.64.128.0/24", "10.64.129.0/24", "10.64.130.0/24"]
database_subnets    = ["10.64.192.0/24", "10.64.193.0/24", "10.64.194.0/24"]
intra_subnets       = ["10.64.224.0/24", "10.64.225.0/24", "10.64.226.0/24"]

cluster_name               = "aiops-platform-prod"
cluster_version            = "1.28"
cluster_endpoint_public_access  = false
cluster_endpoint_private_access = true

node_group_instance_types = ["m6i.xlarge", "m6a.xlarge", "c6i.xlarge"]
node_group_desired_size   = 3
node_group_min_size       = 3
node_group_max_size       = 15
node_group_disk_size      = 100

enable_karpenter                 = true
karpenter_instance_families      = ["m6i", "m6a", "c6i", "c6a", "r6i", "r6a"]

enable_aws_load_balancer_controller = true
enable_external_dns                 = true
enable_cluster_autoscaler           = true
enable_metrics_server               = true
enable_secrets_store_csi_driver     = true
enable_ebs_csi_resizer              = true
enable_efs_csi_driver               = false

ebs_encryption_enabled = true

rds_instance_class     = "db.r6g.xlarge"
rds_allocated_storage  = 200
rds_engine             = "postgres"
rds_engine_version     = "15.3"
rds_database_name      = "aiopsplatform"
rds_username           = "aiops_admin"
rds_password           = ""

elasticache_node_type         = "cache.r6g.large"
elasticache_num_cache_nodes   = 3
elasticache_engine_version    = "7.0"

enable_cloudwatch_logging  = true
cloudwatch_retention_days  = 365

domain_name          = "aiops-platform.internal"
enable_route53       = true
backup_bucket_name   = "aiops-platform-prod-backup"
backup_retention_days = 90

enable_waf       = true
waf_rate_limit   = 5000

kms_key_administrators = []
kms_key_users          = []

ecr_repository_names = [
  "api-gateway",
  "user-service",
  "workflow-service",
  "model-service",
  "notification-service",
  "data-pipeline",
  "monitoring-service",
  "audit-service",
]
