output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = module.vpc.database_subnet_ids
}

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "The endpoint URL for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "The base64-encoded CA certificate for the cluster"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL for the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_group_arn" {
  description = "ARN of the EKS node group"
  value       = module.eks.node_group_arn
}

output "node_group_role_name" {
  description = "The IAM role name for the node group"
  value       = module.eks.node_group_role_name
}

output "kms_key_id" {
  description = "The ID of the KMS key"
  value       = module.kms.kms_key_id
}

output "kms_key_arn" {
  description = "The ARN of the KMS key"
  value       = module.kms.kms_key_arn
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = module.rds.rds_endpoint
  sensitive   = true
}

output "rds_arn" {
  description = "The ARN of the RDS instance"
  value       = module.rds.rds_arn
}

output "rds_database_name" {
  description = "The name of the RDS database"
  value       = module.rds.rds_database_name
}

output "elasticache_endpoint" {
  description = "The connection endpoint for ElastiCache replication group"
  value       = module.elasticache.elasticache_endpoint
  sensitive   = true
}

output "elasticache_port" {
  description = "The port number for ElastiCache"
  value       = module.elasticache.elasticache_port
}

output "load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.eks.load_balancer_controller_role_arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS"
  value       = module.eks.external_dns_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = module.eks.cluster_autoscaler_role_arn
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for EBS CSI Driver"
  value       = module.eks.ebs_csi_role_arn
}

output "ecr_repository_urls" {
  description = "Map of ECR repository names to URLs"
  value       = module.ecr.repository_urls
}

output "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  value       = module.s3.backup_bucket_arn
}

output "backup_bucket_id" {
  description = "ID of the S3 backup bucket"
  value       = module.s3.backup_bucket_id
}

output "cluster_security_group_id" {
  description = "The security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "The security group ID attached to the node group"
  value       = module.eks.node_security_group_id
}

output "karpenter_role_arn" {
  description = "IAM role ARN for Karpenter"
  value       = module.eks.karpenter_role_arn
}

output "private_hosted_zone_id" {
  description = "The Route53 private hosted zone ID"
  value       = module.route53.private_hosted_zone_id
}
