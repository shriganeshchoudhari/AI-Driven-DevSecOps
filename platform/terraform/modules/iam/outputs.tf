output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_cluster_role_name" {
  description = "Name of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.name
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_role_name" {
  description = "Name of the EKS node IAM role"
  value       = aws_iam_role.eks_node.name
}

output "eks_node_instance_profile_name" {
  description = "Name of the EKS node instance profile"
  value       = aws_iam_instance_profile.eks_node.name
}

output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_node[0].arn : ""
}

output "karpenter_node_role_name" {
  description = "Name of the Karpenter node IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_node[0].name : ""
}

output "karpenter_instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = var.enable_karpenter ? aws_iam_instance_profile.karpenter_node[0].name : ""
}

output "karpenter_instance_profile_arn" {
  description = "ARN of the Karpenter node instance profile"
  value       = var.enable_karpenter ? aws_iam_instance_profile.karpenter_node[0].arn : ""
}
