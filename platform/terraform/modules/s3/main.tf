data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  log_bucket = var.enable_logging && var.log_bucket_name != "" ? var.log_bucket_name : "${var.project_name}-${var.environment}-s3-logs"
}

# ---------------------------------------------------------------------------
# Terraform State Bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "${var.project_name}-terraform-state-${var.aws_account_id}"
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-terraform-state"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceTLS"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Backup Bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "backup" {
  bucket        = var.backup_bucket_name
  force_destroy = false
  object_lock_enabled = true

  tags = merge(var.tags, {
    Name        = var.backup_bucket_name
    Environment = var.environment
  })
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    id     = "transition-to-glacier"
    status = "Enabled"
    filter {}
    transition {
      days          = var.backup_retention_days
      storage_class = "GLACIER_IR"
    }
    transition {
      days          = var.backup_retention_days + 90
      storage_class = "DEEP_ARCHIVE"
    }
    expiration {
      days = var.backup_retention_days + 365
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceTLS"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_object_lock_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.backup_retention_days
    }
  }
}

# ---------------------------------------------------------------------------
# VPC Flow Logs Bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "flow_logs" {
  count = var.flow_logs_bucket_enabled ? 1 : 0

  bucket        = "${var.project_name}-${var.environment}-vpc-flow-logs"
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-vpc-flow-logs"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count = var.flow_logs_bucket_enabled ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = var.flow_logs_bucket_enabled ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = var.flow_logs_bucket_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = var.flow_logs_bucket_enabled ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id
  rule {
    id     = "expire-flow-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Container Image Cache Bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "container_cache" {
  bucket        = "${var.project_name}-${var.environment}-container-cache"
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-container-cache"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_versioning" "container_cache" {
  bucket = aws_s3_bucket.container_cache.id
  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "container_cache" {
  bucket = aws_s3_bucket.container_cache.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "container_cache" {
  bucket                  = aws_s3_bucket.container_cache.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "container_cache" {
  bucket = aws_s3_bucket.container_cache.id
  rule {
    id     = "expire-old-cache"
    status = "Enabled"
    filter {}
    expiration {
      days = 14
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ---------------------------------------------------------------------------
# Log Archive Bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "log_archive" {
  bucket        = var.enable_logging ? local.log_bucket : "${var.project_name}-${var.environment}-log-archive"
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-log-archive"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_versioning" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "log_archive" {
  bucket                  = aws_s3_bucket.log_archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  rule {
    id     = "transition-logs"
    status = "Enabled"
    filter {}
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 60
      storage_class = "GLACIER_IR"
    }
    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
    expiration {
      days = 365
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceTLS"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.log_archive.arn,
          "${aws_s3_bucket.log_archive.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Intelligent Tiering
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_intelligent_tiering_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  name   = "entire-bucket"
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  name   = "entire-bucket"
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}

# ---------------------------------------------------------------------------
# DynamoDB Table for Terraform State Locking
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-terraform-locks"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# S3 Access Logs (delivery to log archive bucket)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_logging" "backup" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.backup.id
  target_bucket = aws_s3_bucket.log_archive.id
  target_prefix = "logs/backup/"
}

resource "aws_s3_bucket_logging" "terraform_state" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.log_archive.id
  target_prefix = "logs/terraform-state/"
}
