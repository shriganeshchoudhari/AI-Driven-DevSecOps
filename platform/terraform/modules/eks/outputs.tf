output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "Cluster security group ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "node_group_arn" {
  description = "Node group ARN"
  value       = aws_eks_node_group.main.arn
}

output "node_group_role_name" {
  description = "Node group IAM role name"
  value       = var.node_role_arn
}

output "node_security_group_id" {
  description = "Node security group ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "karpenter_role_arn" {
  description = "Karpenter IAM role ARN"
  value       = var.karpenter_role_arn
}

output "load_balancer_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  value       = var.enable_load_balancer_controller ? aws_iam_role.load_balancer_controller[0].arn : ""
}

output "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].arn : ""
}

output "external_dns_role_arn" {
  description = "IRSA role ARN for ExternalDNS"
  value       = var.enable_external_dns ? aws_iam_role.external_dns[0].arn : ""
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver"
  value       = var.enable_ebs_csi_driver ? aws_iam_role.ebs_csi[0].arn : ""
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = var.oidc_provider_enabled ? aws_iam_openid_connect_provider.main[0].arn : ""
}

output "oidc_provider_url" {
  description = "OIDC provider URL"
  value       = var.oidc_provider_enabled ? aws_iam_openid_connect_provider.main[0].url : ""
}

output "cluster_primary_security_group_id" {
  description = "Primary security group ID for the cluster"
  value       = try(aws_eks_cluster.main.vpc_config[0].cluster_security_group_id, "")
}

output "cluster_addons" {
  description = "Map of cluster addon versions"
  value = {
    vpc_cni     = aws_eks_addon.vpc_cni.addon_version
    coredns     = aws_eks_addon.coredns.addon_version
    kube_proxy  = aws_eks_addon.kube_proxy.addon_version
    ebs_csi     = try(aws_eks_addon.ebs_csi[0].addon_version, "")
  }
}
