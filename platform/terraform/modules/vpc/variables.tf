variable "name" {
  description = "Name prefix for all VPC resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "database_subnets" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
}

variable "intra_subnets" {
  description = "CIDR blocks for intra-cluster subnets (no NAT)"
  type        = list(string)
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention period for flow log CloudWatch logs"
  type        = number
  default     = 365
}

variable "enable_s3_vpc_endpoint" {
  description = "Enable S3 Gateway VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_dynamodb_vpc_endpoint" {
  description = "Enable DynamoDB Gateway VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_ecr_vpc_endpoints" {
  description = "Enable ECR API and DKR interface endpoints"
  type        = bool
  default     = true
}

variable "enable_private_api_endpoints" {
  description = "Enable STS, SSM, EC2, Secrets Manager interface endpoints"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
