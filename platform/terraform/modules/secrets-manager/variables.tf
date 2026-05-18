variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for secret encryption"
  type        = string
}

variable "secrets" {
  description = "Map of secret names to their description and value"
  type = map(object({
    description = string
    value       = string
  }))
}

variable "rotation_days" {
  description = "Number of days between automatic rotations"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
