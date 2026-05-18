data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  db_name = var.database_name
}

# ---------------------------------------------------------------------------
# DB Subnet Group
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Database subnet group for ${var.project_name}-${var.environment}"
  subnet_ids  = var.database_subnets

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-db-subnet-group"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# DB Parameter Group
# ---------------------------------------------------------------------------
resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-params"
  family      = "${var.engine}${var.engine_version >= "15" ? "15" : split(".", var.engine_version)[0]}"
  description = "Custom parameter group for ${var.project_name}-${var.environment}"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "log_temp_files"
    value = "0"
  }

  parameter {
    name  = "log_autovacuum_min_duration"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,auto_explain"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "ALL"
  }

  parameter {
    name  = "auto_explain.log_min_duration"
    value = "1000"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "work_mem"
    value = "{DBInstanceClassMemory/32768}"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "{DBInstanceClassMemory/16}"
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-db-params"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Security Group for RDS
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }

  ingress {
    description     = "PostgreSQL from EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = []
    self            = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# DB Instance
# ---------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}"

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = local.db_name
  username = var.master_username
  password = var.master_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  iops                  = 3000
  storage_throughput    = 125
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot   = true
  delete_automated_backups = false
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.project_name}-${var.environment}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = var.kms_key_arn

  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade",
  ]

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  auto_minor_version_upgrade = true
  allow_major_version_upgrade = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
  })


}

# ---------------------------------------------------------------------------
# Enhanced Monitoring Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-rds-monitoring-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# RDS Proxy (Optional - for connection pooling)
# ---------------------------------------------------------------------------
resource "aws_db_proxy" "main" {
  count = var.multi_az ? 1 : 0

  name                   = "${var.project_name}-${var.environment}-db-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy[0].arn
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds.id]

  auth {
    auth_scheme = "SECRETS"
    description = "RDS Proxy authentication"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.rds_proxy[0].arn
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-db-proxy"
    Environment = var.environment
  })
}

resource "aws_db_proxy_default_target_group" "main" {
  count = var.multi_az ? 1 : 0

  db_proxy_name = aws_db_proxy.main[0].name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
    session_pinning_filters      = ["EXCLUDE_VARIABLE_SETS"]
  }
}

resource "aws_db_proxy_target" "main" {
  count = var.multi_az ? 1 : 0

  db_instance_identifier = aws_db_instance.main.id
  db_proxy_name          = aws_db_proxy.main[0].name
  target_group_name      = aws_db_proxy_default_target_group.main[0].name
}

resource "aws_iam_role" "rds_proxy" {
  count = var.multi_az ? 1 : 0

  name = "${var.project_name}-${var.environment}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-rds-proxy-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "rds_proxy" {
  count = var.multi_az ? 1 : 0

  role       = aws_iam_role.rds_proxy[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSDirectoryServiceAccess"
}

resource "aws_secretsmanager_secret" "rds_proxy" {
  count = var.multi_az ? 1 : 0

  name                    = "${var.project_name}-${var.environment}-rds-proxy-secret"
  description             = "Secret for RDS Proxy authentication"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-rds-proxy-secret"
    Environment = var.environment
  })
}

resource "aws_secretsmanager_secret_version" "rds_proxy" {
  count = var.multi_az ? 1 : 0

  secret_id     = aws_secretsmanager_secret.rds_proxy[0].id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = aws_db_instance.main.password
    engine   = aws_db_instance.main.engine
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}
