data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Secrets Manager Secrets
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "main" {
  for_each = var.secrets

  name                    = "${var.project_name}-${var.environment}-${each.key}"
  description             = each.value.description
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-${each.key}"
    Environment = var.environment
  })
}

resource "aws_secretsmanager_secret_version" "main" {
  for_each = var.secrets

  secret_id     = aws_secretsmanager_secret.main[each.key].id
  secret_string = each.value.value
}

# ---------------------------------------------------------------------------
# Secret Rotation (Lambda-based)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret_rotation" "main" {
  for_each = {
    for k, v in aws_secretsmanager_secret.main : k => v
    if contains(keys(var.secrets[k]), "rotate") && var.secrets[k].rotate
  }

  secret_id           = each.value.id
  rotation_lambda_arn = try(aws_lambda_function.secret_rotation[0].arn, "")
  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}

resource "aws_lambda_function" "secret_rotation" {
  count = length([for k, v in var.secrets : v if try(v.rotate, false)]) > 0 ? 1 : 0

  filename         = "${path.module}/rotation_lambda.zip"
  function_name    = "${var.project_name}-${var.environment}-secret-rotation"
  role             = aws_iam_role.secret_rotation[0].arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 128
  publish          = true

  environment {
    variables = {
      REGION = data.aws_region.current.name
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-secret-rotation"
    Environment = var.environment
  })
}

resource "aws_iam_role" "secret_rotation" {
  count = length([for k, v in var.secrets : v if try(v.rotate, false)]) > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-secret-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-secret-rotation-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "secret_rotation_basic" {
  count = length([for k, v in var.secrets : v if try(v.rotate, false)]) > 0 ? 1 : 0

  role       = aws_iam_role.secret_rotation[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "secret_rotation_secrets" {
  count = length([for k, v in var.secrets : v if try(v.rotate, false)]) > 0 ? 1 : 0

  role       = aws_iam_role.secret_rotation[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/SecretsManagerReadWrite"
}

# ---------------------------------------------------------------------------
# Secret Resource Policy (Cross-Account Access)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret_policy" "main" {
  for_each = {
    for k, v in var.secrets : k => v
    if try(v.cross_account_ids, null) != null
  }

  secret_arn = aws_secretsmanager_secret.main[each.key].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CrossAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = [for aid in try(each.value.cross_account_ids, []) : "arn:${data.aws_partition.current.partition}:iam::${aid}:root"]
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "*"
      }
    ]
  })
}
