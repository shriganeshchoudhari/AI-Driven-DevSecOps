data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  multi_region = var.enable_multi_region
}

data "aws_iam_policy_document" "key_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.key_administrators) > 0 ? [1] : []
    content {
      sid    = "Allow access for Key Administrators"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.key_administrators
      }
      actions = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
        "kms:RotateKeyOnDemand",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []
    content {
      sid    = "Allow use of the key"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.key_users
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "ebs" {
  description             = "KMS key for EBS volume encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  is_enabled              = true
  multi_region            = local.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-kms-ebs"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.project_name}-${var.environment}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  is_enabled              = true
  multi_region            = local.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-kms-s3"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  is_enabled              = true
  multi_region            = local.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-kms-rds"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  is_enabled              = true
  multi_region            = local.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-kms-secrets"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster secret encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  is_enabled              = true
  multi_region            = local.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-kms-eks"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-${var.environment}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_kms_key" "ecr" {
  description             = "KMS key for ECR encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  is_enabled              = true
  multi_region            = local.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-kms-ecr"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.project_name}-${var.environment}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_kms_key" "elasticache" {
  description             = "KMS key for ElastiCache encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  is_enabled              = true
  multi_region            = local.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-kms-elasticache"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "elasticache" {
  name          = "alias/${var.project_name}-${var.environment}-elasticache"
  target_key_id = aws_kms_key.elasticache.key_id
}
