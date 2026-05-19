resource "random_string" "auth_token" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# ---------------------------------------------------------------------------
# ElastiCache Subnet Group
# ---------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-redis-subnet-group"
  description = "ElastiCache subnet group for ${var.project_name}-${var.environment}"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-redis-subnet-group"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# ElastiCache Parameter Group
# ---------------------------------------------------------------------------
resource "aws_elasticache_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-redis-params"
  family      = "redis7"
  description = "Custom parameter group for ${var.project_name}-${var.environment}"

  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "active-defrag-ignore-bytes"
    value = "104857600"
  }

  parameter {
    name  = "active-defrag-cycle-min"
    value = "1"
  }

  parameter {
    name  = "active-defrag-cycle-max"
    value = "25"
  }

  parameter {
    name  = "active-defrag-threshold-lower"
    value = "10"
  }

  parameter {
    name  = "active-defrag-threshold-upper"
    value = "100"
  }

  parameter {
    name  = "lfu-decay-time"
    value = "1"
  }

  parameter {
    name  = "lfu-log-factor"
    value = "10"
  }

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  parameter {
    name  = "tcp-keepalive"
    value = "300"
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-redis-params"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Security Group for ElastiCache
# ---------------------------------------------------------------------------
resource "aws_security_group" "elasticache" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }

  ingress {
    description     = "Redis cluster bus from EKS nodes"
    from_port       = 16379
    to_port         = 16379
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-redis-sg"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# ElastiCache Replication Group (Cluster Mode Enabled)
# ---------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "main" {
  replication_group_id          = "${var.project_name}-${var.environment}-redis"
  description                   = "ElastiCache Redis for ${var.project_name}-${var.environment}"

  node_type            = var.node_type
  num_cache_clusters   = var.automatic_failover ? var.num_cache_nodes : 1
  port                 = 6379

  engine         = "redis"
  engine_version = var.engine_version

  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.elasticache.id]

  automatic_failover_enabled = var.automatic_failover
  multi_az_enabled           = var.automatic_failover && var.num_cache_nodes >= 2

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true
  auth_token                 = random_string.auth_token.result

  auto_minor_version_upgrade = true

  maintenance_window = "sun:06:00-sun:07:00"
  snapshot_window    = "04:00-05:00"
  snapshot_retention_limit = var.backup_retention_days

  data_tiering_enabled = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-redis"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Store Auth Token in Secrets Manager
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "elasticache_auth" {
  name                    = "${var.project_name}-${var.environment}-redis-auth-v2"
  description             = "ElastiCache Redis auth token for ${var.project_name}-${var.environment}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-redis-auth-v2"
    Environment = var.environment
  })
}

resource "aws_secretsmanager_secret_version" "elasticache_auth" {
  secret_id     = aws_secretsmanager_secret.elasticache_auth.id
  secret_string = jsonencode({
    auth_token            = aws_elasticache_replication_group.main.auth_token
    primary_endpoint      = aws_elasticache_replication_group.main.primary_endpoint_address
    reader_endpoint       = aws_elasticache_replication_group.main.reader_endpoint_address
    port                  = aws_elasticache_replication_group.main.port
    replication_group_id  = aws_elasticache_replication_group.main.id
  })
}
