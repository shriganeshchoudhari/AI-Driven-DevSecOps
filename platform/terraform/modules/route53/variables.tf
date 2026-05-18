variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "domain_name" {
  description = "Domain name for Route53 zones"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for private hosted zone association"
  type        = string
}

variable "create_public_zone" {
  description = "Create a public hosted zone"
  type        = bool
  default     = false
}

variable "create_private_zone" {
  description = "Create a private hosted zone"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
