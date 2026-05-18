data "aws_partition" "current" {}

locals {
  az_count = length(var.availability_zones)
  vpc_name = "${var.name}-vpc"
}

resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
  instance_tenancy                 = "default"
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = false

  tags = merge(var.tags, {
    Name        = local.vpc_name
    Environment = var.environment
  })
}

resource "aws_vpc_dhcp_options" "main" {
  domain_name         = "${data.aws_region.current.name}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = merge(var.tags, {
    Name = "${var.name}-dhcp-options"
  })
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Public Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                          = "${var.name}-public-${var.availability_zones[count.index]}"
    Environment                                   = var.environment
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${var.name}"            = "shared"
  })
}

# ---------------------------------------------------------------------------
# Private Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                                          = "${var.name}-private-${var.availability_zones[count.index]}"
    Environment                                   = var.environment
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.name}"            = "shared"
  })
}

# ---------------------------------------------------------------------------
# Database Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "database" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.database_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name        = "${var.name}-database-${var.availability_zones[count.index]}"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Intra Subnets (for internal cluster traffic, no NAT)
# ---------------------------------------------------------------------------
resource "aws_subnet" "intra" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.intra_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                                          = "${var.name}-intra-${var.availability_zones[count.index]}"
    Environment                                   = var.environment
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.name}"            = "shared"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name        = "${var.name}-igw"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.az_count
  domain = "vpc"

  tags = merge(var.tags, {
    Name        = "${var.name}-nat-eip-${var.availability_zones[count.index]}"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# NAT Gateways (one per AZ for HA)
# ---------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = local.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name        = "${var.name}-nat-${var.availability_zones[count.index]}"
    Environment = var.environment
  })

  depends_on = [aws_internet_gateway.main]
}

# ---------------------------------------------------------------------------
# Public Route Table
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name        = "${var.name}-public-rt"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private Route Tables (one per AZ)
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name        = "${var.name}-private-rt-${var.availability_zones[count.index]}"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "intra" {
  count = local.az_count

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra[count.index].id
}

# ---------------------------------------------------------------------------
# Intra Route Tables (no NAT, only VPC endpoints)
# ---------------------------------------------------------------------------
resource "aws_route_table" "intra" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name        = "${var.name}-intra-rt-${var.availability_zones[count.index]}"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Database Subnet Group
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.name}-database-subnet-group"
  description = "Database subnet group for ${var.name}"
  subnet_ids  = aws_subnet.database[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-database-subnet-group"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoints - Gateway
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_vpc_endpoint ? 1 : 0

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    aws_route_table.intra[*].id,
    [aws_route_table.public.id],
  )

  tags = merge(var.tags, {
    Name        = "${var.name}-s3-vpc-endpoint"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_dynamodb_vpc_endpoint ? 1 : 0

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    aws_route_table.intra[*].id,
  )

  tags = merge(var.tags, {
    Name        = "${var.name}-dynamodb-vpc-endpoint"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Security Group for VPC Endpoints (Interface)
# ---------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_private_api_endpoints || var.enable_ecr_vpc_endpoints ? 1 : 0

  name        = "${var.name}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.name}-vpc-endpoints-sg"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoints - Interface (Private API)
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "sts" {
  count = var.enable_private_api_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id

  security_group_ids = aws_security_group.vpc_endpoints[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-sts-vpc-endpoint"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_private_api_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id

  security_group_ids = aws_security_group.vpc_endpoints[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-ssm-vpc-endpoint"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.enable_private_api_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id

  security_group_ids = aws_security_group.vpc_endpoints[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-ssmmessages-vpc-endpoint"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ec2" {
  count = var.enable_private_api_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id

  security_group_ids = aws_security_group.vpc_endpoints[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-ec2-vpc-endpoint"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_private_api_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id

  security_group_ids = aws_security_group.vpc_endpoints[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-secretsmanager-vpc-endpoint"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_ecr_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id

  security_group_ids = aws_security_group.vpc_endpoints[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-ecr-api-vpc-endpoint"
    Environment = var.environment
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_ecr_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id

  security_group_ids = aws_security_group.vpc_endpoints[*].id

  tags = merge(var.tags, {
    Name        = "${var.name}-ecr-dkr-vpc-endpoint"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# VPC Flow Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "${var.name}-vpc-flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = merge(var.tags, {
    Name        = "${var.name}-vpc-flow-logs"
    Environment = var.environment
  })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.name}-vpc-flow-logs-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  role       = aws_iam_role.flow_logs[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(var.tags, {
    Name        = "${var.name}-vpc-flow-log"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Security Groups for EKS
# ---------------------------------------------------------------------------
resource "aws_security_group" "cluster" {
  name        = "${var.name}-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name                                        = "${var.name}-eks-cluster-sg"
    Environment                                 = var.environment
    "kubernetes.io/cluster/${var.name}"          = "owned"
  })
}

resource "aws_security_group" "node" {
  name        = "${var.name}-eks-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Node-to-node communication"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
  }

  ingress {
    description     = "Cluster control plane to node"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.cluster.id]
  }

  ingress {
    description = "Allow VPN/RDP/SSH from VPC CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name                                        = "${var.name}-eks-node-sg"
    Environment                                 = var.environment
    "kubernetes.io/cluster/${var.name}"          = "owned"
  })
}
