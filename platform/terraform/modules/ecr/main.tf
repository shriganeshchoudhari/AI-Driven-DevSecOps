data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# ECR Repositories
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "main" {
  for_each = toset(var.repository_names)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != "" ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn != "" ? var.kms_key_arn : null
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}/${each.key}"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# ECR Lifecycle Policies
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "main" {
  for_each = var.lifecycle_policy ? toset(var.repository_names) : toset([])

  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 50 images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["release-", "v", "stable-"]
          countType   = "imageCountMoreThan"
          countNumber = 50
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countNumber = 14
          countUnit   = "days"
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Expire tagged images older than 90 days (non-release)"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countNumber = 90
          countUnit   = "days"
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# ECR Repository Policy (Least Privilege)
# ---------------------------------------------------------------------------
resource "aws_ecr_repository_policy" "main" {
  for_each = toset(var.repository_names)

  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root",
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:ListImages",
        ]
      },
      {
        Sid    = "DenyUntrustedAccounts"
        Effect = "Deny"
        Principal = "*"
        Action = "ecr:*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount": data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# ECR Registry Scanning Configuration (Enhanced)
# ---------------------------------------------------------------------------
resource "aws_ecr_registry_scanning_configuration" "main" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

# ---------------------------------------------------------------------------
# ECR Registry Policy
# ---------------------------------------------------------------------------
resource "aws_ecr_registry_policy" "main" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReplicationAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:ReplicateImage",
        ]
        Resource = "*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# ECR Cross-Account Access (if needed)
# ---------------------------------------------------------------------------
# resource "aws_ecr_repository_policy" "cross_account" {
#   count      = length(var.cross_account_ids) > 0 ? length(var.repository_names) : 0
#   repository = aws_ecr_repository.main[var.repository_names[count.index]].name
#   policy     = data.aws_iam_policy_document.cross_account.json
# }
