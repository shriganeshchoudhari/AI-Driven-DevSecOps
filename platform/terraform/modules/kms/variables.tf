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

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "key_administrators" {
  description = "List of IAM ARNs for key administrators"
  type        = list(string)
  default     = []
}

variable "key_users" {
  description = "List of IAM ARNs for key users"
  type        = list(string)
  default     = []
}

variable "enable_multi_region" {
  description = "Enable multi-region keys for DR"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
