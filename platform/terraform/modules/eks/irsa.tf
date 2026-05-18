data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  oidc_url_without_protocol = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

# ---------------------------------------------------------------------------
# IRSA: AWS Load Balancer Controller
# ---------------------------------------------------------------------------
resource "aws_iam_role" "load_balancer_controller" {
  count = var.enable_load_balancer_controller ? 1 : 0

  name = "${var.cluster_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.main[0].arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url_without_protocol}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${local.oidc_url_without_protocol}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-alb-controller-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "load_balancer_controller" {
  count = var.enable_load_balancer_controller ? 1 : 0

  name = "${var.cluster_name}-alb-controller-policy"
  role = aws_iam_role.load_balancer_controller[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:DescribeTags",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAvailabilityZones",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "iam:CreateServiceLinkedRole",
          "tag:GetResources",
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IRSA: Cluster Autoscaler
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name = "${var.cluster_name}-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.main[0].arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url_without_protocol}:sub" : "system:serviceaccount:kube-system:cluster-autoscaler"
            "${local.oidc_url_without_protocol}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-cluster-autoscaler-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name = "${var.cluster_name}-cluster-autoscaler-policy"
  role = aws_iam_role.cluster_autoscaler[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IRSA: ExternalDNS
# ---------------------------------------------------------------------------
resource "aws_iam_role" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name = "${var.cluster_name}-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.main[0].arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url_without_protocol}:sub" : "system:serviceaccount:kube-system:external-dns"
            "${local.oidc_url_without_protocol}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-external-dns-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name = "${var.cluster_name}-external-dns-policy"
  role = aws_iam_role.external_dns[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:GetChange",
          "route53:GetHostedZone",
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IRSA: EBS CSI Driver
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.main[0].arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url_without_protocol}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${local.oidc_url_without_protocol}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-ebs-csi-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------------------------------------------------------------------
# IRSA: Cert Manager
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name = "${var.cluster_name}-cert-manager-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.main[0].arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url_without_protocol}:sub" : "system:serviceaccount:cert-manager:cert-manager"
            "${local.oidc_url_without_protocol}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-cert-manager-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name = "${var.cluster_name}-cert-manager-policy"
  role = aws_iam_role.cert_manager[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ListHostedZones",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IRSA: Karpenter Controller
# ---------------------------------------------------------------------------
resource "aws_iam_role" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.cluster_name}-karpenter-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.main[0].arn
        }
        Condition = {
          StringEquals = {
            "${local.oidc_url_without_protocol}:sub" : "system:serviceaccount:karpenter:karpenter"
            "${local.oidc_url_without_protocol}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-karpenter-controller-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name = "${var.cluster_name}-karpenter-controller-policy"
  role = aws_iam_role.karpenter_controller[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:DeleteLaunchTemplate",
          "ec2:DeleteLaunchTemplateVersions",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:CreateFleet",
          "ec2:CreateTags",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeImages",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ec2:TerminateInstances",
          "ec2:DeleteTags",
          "ec2:RunInstances",
          "iam:CreateInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:PassRole",
          "pricing:DescribeServices",
          "pricing:GetProducts",
          "eks:DescribeCluster",
        ]
        Resource = "*"
      }
    ]
  })
}
