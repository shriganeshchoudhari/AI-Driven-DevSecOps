data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Karpenter Kubernetes Namespace
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  metadata {
    annotations = {
      name = "karpenter"
    }
    labels = {
      name                                   = "karpenter"
      "kubernetes.io/metadata.name"          = "karpenter"
      "pod-security.kubernetes.io/enforce"   = "privileged"
    }
    name = "karpenter"
  }

  depends_on = [aws_eks_cluster.main]
}

# ---------------------------------------------------------------------------
# Karpenter NodePool (v1beta1 API)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "karpenter_nodepool" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  namespace: karpenter
spec:
  template:
    spec:
      requirements:
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand", "spot"]
        - key: "node.kubernetes.io/instance-type"
          operator: In
          values: ${jsonencode([for f in var.karpenter_instance_families : "${f}.xlarge", "${f}.2xlarge", "${f}.4xlarge"])}
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ${jsonencode(var.private_subnet_ids)}
      nodeClassRef:
        name: default
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
    budgets:
      - nodes: "10%"
  limits:
    cpu: 1000
    memory: 4000Gi
  weight: 10
YAML

  depends_on = [aws_eks_cluster.main, kubernetes_namespace.karpenter]
}

# ---------------------------------------------------------------------------
# Karpenter EC2NodeClass (v1beta1)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "karpenter_ec2nodeclass" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
  namespace: karpenter
spec:
  amiFamily: AL2
  role: ${var.karpenter_role_arn != "" ? var.karpenter_role_arn : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-karpenter-node-role"}
  subnetSelectorTerms:
    - tags:
        "kubernetes.io/cluster/${var.cluster_name}": shared
  securityGroupSelectorTerms:
    - tags:
        "kubernetes.io/cluster/${var.cluster_name}": owned
  instanceProfile: ${var.karpenter_instance_profile_name != "" ? var.karpenter_instance_profile_name : "${var.cluster_name}-karpenter-node-instance-profile"}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        encrypted: true
  metadataOptions:
    httpEndpoint: enabled
    httpTokens: required
    httpPutResponseHopLimit: 2
  tags:
    Environment: ${var.environment}
    ManagedBy: karpenter
    Cluster: ${var.cluster_name}
  detailedMonitoring: true
YAML

  depends_on = [aws_eks_cluster.main, kubernetes_namespace.karpenter]
}

# ---------------------------------------------------------------------------
# Karpenter Provisioner (legacy v1alpha5 API - compatibility)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "karpenter_provisioner" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
  namespace: karpenter
spec:
  requirements:
    - key: "karpenter.sh/capacity-type"
      operator: In
      values: ["on-demand", "spot"]
    - key: "node.kubernetes.io/instance-type"
      operator: In
      values: ${jsonencode([for f in var.karpenter_instance_families : "${f}.large", "${f}.xlarge", "${f}.2xlarge", "${f}.4xlarge"])}
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: ${jsonencode(var.private_subnet_ids)}
  limits:
    resources:
      cpu: 1000
      memory: 4000Gi
  consolidation:
    enabled: true
  ttlSecondsAfterEmpty: 30
  ttlSecondsUntilExpired: 2592000
  providerRef:
    name: default
YAML

  depends_on = [aws_eks_cluster.main, kubernetes_namespace.karpenter]
}

# ---------------------------------------------------------------------------
# Karpenter AWSNodeTemplate (legacy v1alpha1)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "karpenter_awsnode_template" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: default
  namespace: karpenter
spec:
  subnetSelector:
    "kubernetes.io/cluster/${var.cluster_name}": shared
  securityGroupSelector:
    "kubernetes.io/cluster/${var.cluster_name}": owned
  instanceProfile: ${var.karpenter_instance_profile_name != "" ? var.karpenter_instance_profile_name : "${var.cluster_name}-karpenter-node-instance-profile"}
  amiFamily: AL2
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        encrypted: true
  detailedMonitoring: true
  metadataOptions:
    httpEndpoint: enabled
    httpTokens: required
    httpPutResponseHopLimit: 2
  tags:
    Environment: ${var.environment}
    ManagedBy: karpenter
YAML

  depends_on = [aws_eks_cluster.main, kubernetes_namespace.karpenter]
}

data "aws_caller_identity" "current" {}
