output "kms_key_id" {
  description = "Default KMS key ID"
  value       = aws_kms_key.ebs.key_id
}

output "kms_key_arn" {
  description = "Default KMS key ARN"
  value       = aws_kms_key.ebs.arn
}

output "ebs_kms_key_id" {
  description = "EBS KMS key ID"
  value       = aws_kms_key.ebs.key_id
}

output "ebs_kms_key_arn" {
  description = "EBS KMS key ARN"
  value       = aws_kms_key.ebs.arn
}

output "s3_kms_key_id" {
  description = "S3 KMS key ID"
  value       = aws_kms_key.s3.key_id
}

output "s3_kms_key_arn" {
  description = "S3 KMS key ARN"
  value       = aws_kms_key.s3.arn
}

output "rds_kms_key_id" {
  description = "RDS KMS key ID"
  value       = aws_kms_key.rds.key_id
}

output "rds_kms_key_arn" {
  description = "RDS KMS key ARN"
  value       = aws_kms_key.rds.arn
}

output "eks_kms_key_id" {
  description = "EKS KMS key ID"
  value       = aws_kms_key.eks.key_id
}

output "eks_kms_key_arn" {
  description = "EKS KMS key ARN"
  value       = aws_kms_key.eks.arn
}

output "ecr_kms_key_id" {
  description = "ECR KMS key ID"
  value       = aws_kms_key.ecr.key_id
}

output "ecr_kms_key_arn" {
  description = "ECR KMS key ARN"
  value       = aws_kms_key.ecr.arn
}

output "secrets_kms_key_id" {
  description = "Secrets Manager KMS key ID"
  value       = aws_kms_key.secrets.key_id
}

output "secrets_kms_key_arn" {
  description = "Secrets Manager KMS key ARN"
  value       = aws_kms_key.secrets.arn
}

output "elasticache_kms_key_id" {
  description = "ElastiCache KMS key ID"
  value       = aws_kms_key.elasticache.key_id
}

output "elasticache_kms_key_arn" {
  description = "ElastiCache KMS key ARN"
  value       = aws_kms_key.elasticache.arn
}
