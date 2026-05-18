data "aws_region" "current" {}

locals {
  region = data.aws_region.current.name
}

# ---------------------------------------------------------------------------
# Private Hosted Zone
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "private" {
  count = var.create_private_zone ? 1 : 0

  name = var.domain_name

  vpc {
    vpc_id = var.vpc_id
  }

  comment = "Private hosted zone for ${var.domain_name} (${var.environment})"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-private-zone"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Public Hosted Zone
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "public" {
  count = var.create_public_zone ? 1 : 0

  name = var.domain_name

  comment = "Public hosted zone for ${var.domain_name} (${var.environment})"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-public-zone"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Wildcard DNS Record for Internal Services
# ---------------------------------------------------------------------------
resource "aws_route53_record" "wildcard" {
  count = var.create_private_zone ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "*.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = ["10.0.0.1"]

  lifecycle {
    ignore_changes = [records, ttl]
  }
}

# ---------------------------------------------------------------------------
# DNS Records for Core Services (CNAME - placeholder)
# ---------------------------------------------------------------------------
resource "aws_route53_record" "api" {
  count = var.create_private_zone ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "api.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["${var.project_name}-${var.environment}-internal.${local.region}.elb.amazonaws.com"]

  lifecycle {
    ignore_changes = [records]
  }
}

resource "aws_route53_record" "grafana" {
  count = var.create_private_zone ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "grafana.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["${var.project_name}-${var.environment}-internal.${local.region}.elb.amazonaws.com"]

  lifecycle {
    ignore_changes = [records]
  }
}

resource "aws_route53_record" "argocd" {
  count = var.create_private_zone ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "argocd.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["${var.project_name}-${var.environment}-internal.${local.region}.elb.amazonaws.com"]

  lifecycle {
    ignore_changes = [records]
  }
}

resource "aws_route53_record" "database" {
  count = var.create_private_zone ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "database.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["${var.project_name}-${var.environment}.${local.region}.rds.amazonaws.com"]

  lifecycle {
    ignore_changes = [records]
  }
}

resource "aws_route53_record" "redis" {
  count = var.create_private_zone ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "redis.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["${var.project_name}-${var.environment}-redis.${local.region}.cache.amazonaws.com"]

  lifecycle {
    ignore_changes = [records]
  }
}

# ---------------------------------------------------------------------------
# Route53 Health Checks
# ---------------------------------------------------------------------------
resource "aws_route53_health_check" "api" {
  count = var.create_private_zone ? 1 : 0

  fqdn              = "api.${var.domain_name}"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/healthz"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-api-health-check"
    Environment = var.environment
  })
}

resource "aws_route53_health_check" "grafana" {
  count = var.create_private_zone ? 1 : 0

  fqdn              = "grafana.${var.domain_name}"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/api/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-grafana-health-check"
    Environment = var.environment
  })
}
