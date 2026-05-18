variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "intra_subnet_ids" {
  description = "Intra subnet IDs"
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_public_access" {
  description = "Enable public endpoint access"
  type        = bool
  default     = false
}

variable "cluster_endpoint_private_access" {
  description = "Enable private endpoint access"
  type        = bool
  default     = true
}

variable "node_group_instance_types" {
  description = "Instance types for node group"
  type        = list(string)
}

variable "node_group_desired_size" {
  description = "Desired node count"
  type        = number
}

variable "node_group_min_size" {
  description = "Minimum node count"
  type        = number
}

variable "node_group_max_size" {
  description = "Maximum node count"
  type        = number
}

variable "node_group_disk_size" {
  description = "Node disk size in GB"
  type        = number
  default     = 100
}

variable "cluster_role_arn" {
  description = "IAM role ARN for EKS cluster"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS nodes"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for cluster encryption"
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group ID for cluster"
  type        = string
}

variable "enable_karpenter" {
  description = "Enable Karpenter provisioning"
  type        = bool
  default     = false
}

variable "karpenter_role_arn" {
  description = "IAM role ARN for Karpenter"
  type        = string
  default     = ""
}

variable "karpenter_instance_families" {
  description = "Allowed instance families for Karpenter"
  type        = list(string)
  default     = []
}

variable "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter nodes"
  type        = string
  default     = ""
}

variable "oidc_provider_enabled" {
  description = "Enable OIDC provider"
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Enable IRSA"
  type        = bool
  default     = true
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 365
}

variable "enable_load_balancer_controller" {
  description = "Create IRSA role for AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Create IRSA role for Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Create IRSA role for ExternalDNS"
  type        = bool
  default     = true
}

variable "enable_ebs_csi_driver" {
  description = "Create IRSA role for EBS CSI Driver"
  type        = bool
  default     = true
}

variable "enable_cert_manager" {
  description = "Create IRSA role for Cert Manager"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
