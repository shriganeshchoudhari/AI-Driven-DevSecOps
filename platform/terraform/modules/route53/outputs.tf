output "private_hosted_zone_id" {
  description = "Private hosted zone ID"
  value       = var.create_private_zone ? aws_route53_zone.private[0].zone_id : ""
}

output "private_hosted_zone_arn" {
  description = "Private hosted zone ARN"
  value       = var.create_private_zone ? aws_route53_zone.private[0].arn : ""
}

output "private_hosted_zone_name" {
  description = "Private hosted zone name"
  value       = var.create_private_zone ? aws_route53_zone.private[0].name : ""
}

output "public_hosted_zone_id" {
  description = "Public hosted zone ID"
  value       = var.create_public_zone ? aws_route53_zone.public[0].zone_id : ""
}

output "public_hosted_zone_arn" {
  description = "Public hosted zone ARN"
  value       = var.create_public_zone ? aws_route53_zone.public[0].arn : ""
}

output "wildcard_record_fqdn" {
  description = "FQDN of the wildcard DNS record"
  value       = var.create_private_zone ? aws_route53_record.wildcard[0].fqdn : ""
}
