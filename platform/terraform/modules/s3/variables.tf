variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "backup_bucket_name" {
  description = "Name for the backup S3 bucket"
  type        = string
}

variable "backup_retention_days" {
  description = "Retention period for backups in days"
  type        = number
  default     = 90
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 encryption"
  type        = string
}

variable "enable_logging" {
  description = "Enable access logging for S3 buckets"
  type        = bool
  default     = true
}

variable "log_bucket_name" {
  description = "Name for the S3 access log bucket"
  type        = string
  default     = ""
}

variable "flow_logs_bucket_enabled" {
  description = "Create VPC flow logs bucket"
  type        = bool
  default     = true
}

variable "intelligent_tiering" {
  description = "Enable intelligent tiering on buckets"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
