aws_region          = "us-west-2"
environment         = "dev"
project_name        = "aiops-platform"

vpc_cidr            = "10.0.0.0/16"
availability_zones  = ["us-west-2a", "us-west-2b"]
private_subnets     = ["10.0.16.0/20", "10.0.32.0/20"]
public_subnets      = ["10.0.128.0/24", "10.0.129.0/24"]
database_subnets    = ["10.0.192.0/24", "10.0.193.0/24"]
intra_subnets       = ["10.0.224.0/24", "10.0.225.0/24"]

cluster_name               = "aiops-platform-dev"
cluster_version            = "1.28"
cluster_endpoint_public_access  = true
cluster_endpoint_private_access = true

node_group_instance_types = ["m6i.large", "m6a.large"]
node_group_desired_size   = 2
node_group_min_size       = 2
node_group_max_size       = 6
node_group_disk_size      = 50

enable_karpenter                 = false
karpenter_instance_families      = ["m6i", "m6a"]

enable_aws_load_balancer_controller = true
enable_external_dns                 = true
enable_cluster_autoscaler           = true
enable_metrics_server               = true
enable_secrets_store_csi_driver     = true
enable_ebs_csi_resizer              = true
enable_efs_csi_driver               = false

ebs_encryption_enabled = true

rds_instance_class     = "db.r6g.large"
rds_allocated_storage  = 50
rds_engine             = "postgres"
rds_engine_version     = "15.3"
rds_database_name      = "aiopsplatform"
rds_username           = "aiops_admin"
rds_password           = "DevPass12345!"

elasticache_node_type         = "cache.t4g.small"
elasticache_num_cache_nodes   = 1
elasticache_engine_version    = "7.0"

enable_cloudwatch_logging  = true
cloudwatch_retention_days  = 14

domain_name          = "aiops-platform-dev.internal"
enable_route53       = true
backup_bucket_name   = "aiops-platform-dev-backup"
backup_retention_days = 14

enable_waf       = false
waf_rate_limit   = 2000

ecr_repository_names = [
  "api-gateway",
  "user-service",
]
