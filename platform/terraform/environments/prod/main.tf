data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = data.aws_region.current.name
  full_name      = "${var.project_name}-${var.environment}"
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.full_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  database_subnets   = var.database_subnets
  intra_subnets      = var.intra_subnets

  enable_flow_logs            = true
  flow_logs_retention_days    = var.cloudwatch_retention_days
  enable_s3_vpc_endpoint      = true
  enable_dynamodb_vpc_endpoint = true
  enable_ecr_vpc_endpoints    = true
  enable_private_api_endpoints = true

  tags = var.tags
}

module "kms" {
  source = "../../modules/kms"

  environment        = var.environment
  project_name       = var.project_name
  aws_account_id     = local.aws_account_id
  aws_region         = local.aws_region
  key_administrators = var.kms_key_administrators
  key_users          = var.kms_key_users
  enable_multi_region = true

  tags = var.tags
}

module "s3" {
  source = "../../modules/s3"

  environment              = var.environment
  project_name             = var.project_name
  aws_account_id           = local.aws_account_id
  backup_bucket_name       = var.backup_bucket_name != "" ? var.backup_bucket_name : "${var.project_name}-${var.environment}-backup"
  backup_retention_days    = var.backup_retention_days
  kms_key_arn              = module.kms.s3_kms_key_arn
  enable_logging           = true
  log_bucket_name          = "${var.project_name}-${var.environment}-logs"
  flow_logs_bucket_enabled = true
  intelligent_tiering      = true

  tags = var.tags
}

module "ecr" {
  source = "../../modules/ecr"

  environment         = var.environment
  project_name        = var.project_name
  repository_names    = var.ecr_repository_names
  kms_key_arn         = module.kms.ecr_kms_key_arn
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  lifecycle_policy     = true

  tags = var.tags
}

module "iam" {
  source = "../../modules/iam"

  environment     = var.environment
  project_name    = var.project_name
  cluster_name    = var.cluster_name
  aws_account_id  = local.aws_account_id
  aws_region      = local.aws_region
  enable_karpenter = var.enable_karpenter

  tags = var.tags
}

module "eks" {
  source = "../../modules/eks"

  environment             = var.environment
  project_name            = var.project_name
  cluster_name            = var.cluster_name
  cluster_version         = var.cluster_version
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  intra_subnet_ids        = module.vpc.intra_subnet_ids
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access

  node_group_instance_types = var.node_group_instance_types
  node_group_desired_size   = var.node_group_desired_size
  node_group_min_size       = var.node_group_min_size
  node_group_max_size       = var.node_group_max_size
  node_group_disk_size      = var.node_group_disk_size

  cluster_role_arn        = module.iam.eks_cluster_role_arn
  node_role_arn           = module.iam.eks_node_role_arn
  kms_key_arn             = module.kms.eks_kms_key_arn
  cluster_security_group_id = module.vpc.cluster_security_group_id

  enable_karpenter         = var.enable_karpenter
  karpenter_role_arn       = module.iam.karpenter_node_role_arn
  karpenter_instance_families = var.karpenter_instance_families
  karpenter_instance_profile_name = module.iam.karpenter_instance_profile_name

  enable_load_balancer_controller = var.enable_aws_load_balancer_controller
  enable_cluster_autoscaler       = var.enable_cluster_autoscaler
  enable_external_dns             = var.enable_external_dns
  enable_ebs_csi_driver           = true
  enable_cert_manager             = false

  oidc_provider_enabled = var.oidc_provider_enabled
  enable_irsa           = var.enable_irsa

  cloudwatch_retention_days = var.cloudwatch_retention_days

  tags = var.tags

  depends_on = [module.vpc, module.iam, module.kms]
}

module "rds" {
  source = "../../modules/rds"

  environment        = var.environment
  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  database_subnets   = module.vpc.database_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_security_group_id = module.eks.node_security_group_id

  instance_class      = var.rds_instance_class
  allocated_storage   = var.rds_allocated_storage
  engine              = var.rds_engine
  engine_version      = var.rds_engine_version
  database_name       = var.rds_database_name
  master_username     = var.rds_username
  master_password     = var.rds_password != "" ? var.rds_password : random_password.rds_master.result

  kms_key_arn         = module.kms.rds_kms_key_arn
  multi_az            = true
  backup_retention_days = 35
  deletion_protection = true
  performance_insights_enabled = true
  monitoring_interval = 10

  tags = var.tags

  depends_on = [module.vpc, module.kms]
}

module "elasticache" {
  source = "../../modules/elasticache"

  environment          = var.environment
  project_name         = var.project_name
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  eks_security_group_id = module.eks.node_security_group_id

  node_type            = var.elasticache_node_type
  num_cache_nodes      = var.elasticache_num_cache_nodes
  engine_version       = var.elasticache_engine_version
  kms_key_arn          = module.kms.elasticache_kms_key_arn

  automatic_failover   = true
  cluster_mode_enabled = true
  backup_retention_days = 14

  tags = var.tags

  depends_on = [module.vpc]
}

module "route53" {
  source = "../../modules/route53"

  environment     = var.environment
  project_name    = var.project_name
  domain_name     = var.domain_name
  vpc_id          = module.vpc.vpc_id
  create_public_zone  = false
  create_private_zone = true

  tags = var.tags
}

resource "random_password" "rds_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_secretsmanager_secret" "rds_master_password" {
  name                    = "${var.cluster_name}-rds-master-password"
  description             = "Master password for RDS instance ${var.rds_database_name}"
  kms_key_id              = module.kms.secrets_kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-rds-master-password"
  })
}

resource "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id     = aws_secretsmanager_secret.rds_master_password.id
  secret_string = var.rds_password != "" ? var.rds_password : random_password.rds_master.result
}

resource "aws_secretsmanager_secret" "elasticache_auth_token" {
  name                    = "${var.cluster_name}-elasticache-auth-token"
  description             = "Auth token for ElastiCache Redis"
  kms_key_id              = module.kms.secrets_kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-elasticache-auth-token"
  })
}
