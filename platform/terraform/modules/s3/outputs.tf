output "terraform_state_bucket_id" {
  description = "ID of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "backup_bucket_id" {
  description = "ID of the backup S3 bucket"
  value       = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  description = "ARN of the backup S3 bucket"
  value       = aws_s3_bucket.backup.arn
}

output "flow_logs_bucket_id" {
  description = "ID of the VPC flow logs S3 bucket"
  value       = aws_s3_bucket.flow_logs.id
}

output "flow_logs_bucket_arn" {
  description = "ARN of the VPC flow logs S3 bucket"
  value       = aws_s3_bucket.flow_logs.arn
}

output "container_cache_bucket_id" {
  description = "ID of the container image cache bucket"
  value       = aws_s3_bucket.container_cache.id
}

output "log_archive_bucket_id" {
  description = "ID of the log archive bucket"
  value       = aws_s3_bucket.log_archive.id
}

output "log_archive_bucket_arn" {
  description = "ARN of the log archive bucket"
  value       = aws_s3_bucket.log_archive.arn
}

output "terraform_locks_table_name" {
  description = "Name of the DynamoDB table for Terraform state locks"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "terraform_locks_table_arn" {
  description = "ARN of the DynamoDB table for Terraform state locks"
  value       = aws_dynamodb_table.terraform_locks.arn
}
