output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = aws_vpc.main.arn
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = aws_subnet.database[*].id
}

output "intra_subnet_ids" {
  description = "List of intra subnet IDs"
  value       = aws_subnet.intra[*].id
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDRs"
  value       = aws_subnet.private[*].cidr_block
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDRs"
  value       = aws_subnet.public[*].cidr_block
}

output "database_subnet_cidrs" {
  description = "List of database subnet CIDRs"
  value       = aws_subnet.database[*].cidr_block
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_public_ips" {
  description = "List of NAT Gateway public EIPs"
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.node.id
}

output "database_subnet_group_name" {
  description = "Database subnet group name"
  value       = aws_db_subnet_group.main.name
}

output "vpc_flow_log_group_name" {
  description = "CloudWatch log group for VPC flow logs"
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}
