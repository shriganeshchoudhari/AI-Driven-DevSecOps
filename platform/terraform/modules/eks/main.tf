data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  cluster_full_name = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# EKS Cluster
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = var.cluster_role_arn

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access ? ["0.0.0.0/0"] : []
    security_group_ids      = [var.cluster_security_group_id]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
    ip_family         = "ipv4"
  }

  tags = merge(var.tags, {
    Name        = var.cluster_name
    Environment = var.environment
  })

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ---------------------------------------------------------------------------
# EKS Node Group
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-managed-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_group_instance_types
  disk_size      = var.node_group_disk_size

  scaling_config {
    desired_size = var.node_group_desired_size
    min_size     = var.node_group_min_size
    max_size     = var.node_group_max_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  capacity_type = "ON_DEMAND"

  launch_template {
    name    = aws_launch_template.node.name
    version = aws_launch_template.node.latest_version
  }

  labels = {
    "nodegroup-type" = "managed-system"
    "environment"    = var.environment
  }

  tags = merge(var.tags, {
    Name                                          = "${var.cluster_name}-managed-ng"
    Environment                                   = var.environment
    "kubernetes.io/cluster/${var.cluster_name}"    = "owned"
  })

  depends_on = [aws_eks_cluster.main]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ---------------------------------------------------------------------------
# Launch Template for Node Group
# ---------------------------------------------------------------------------
resource "aws_launch_template" "node" {
  name_prefix   = "${var.cluster_name}-node-lt-"
  description   = "Launch template for EKS managed node group"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_group_disk_size
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name        = "${var.cluster_name}-node"
      Environment = var.environment
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name        = "${var.cluster_name}-node-volume"
      Environment = var.environment
    })
  }

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-node-lt"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# EKS Add-ons
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = null
  service_account_role_arn    = aws_iam_role.ebs_csi[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# OIDC Provider
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "main" {
  count = var.oidc_provider_enabled ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-oidc-provider"
    Environment = var.environment
  })
}

data "tls_certificate" "cluster" {
  count = var.oidc_provider_enabled ? 1 : 0

  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ---------------------------------------------------------------------------
# Cluster Security Group Rules
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "cluster_inbound_private_subnets" {
  description       = "Allow private subnets to reach cluster API"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.private_subnet_ids[*]
  security_group_id = var.cluster_security_group_id
}

resource "aws_security_group_rule" "cluster_inbound_intra_subnets" {
  count             = length(var.intra_subnet_ids) > 0 ? 1 : 0
  description       = "Allow intra subnets to reach cluster API"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.intra_subnet_ids[*]
  security_group_id = var.cluster_security_group_id
}

resource "aws_security_group_rule" "cluster_outbound_to_nodes" {
  description              = "Allow cluster to communicate with nodes"
  type                     = "egress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = var.cluster_security_group_id
  security_group_id        = var.cluster_security_group_id
}

# ---------------------------------------------------------------------------
# EKS Access Entries
# ---------------------------------------------------------------------------
resource "aws_eks_access_entry" "admin" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
  kubernetes_groups = ["system:masters"]
  type              = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"

  access_scope {
    type = "cluster"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group for EKS
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_retention_days

  tags = merge(var.tags, {
    Name        = "${var.cluster_name}-cluster-logs"
    Environment = var.environment
  })
}
