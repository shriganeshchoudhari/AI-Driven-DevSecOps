output "secret_arns" {
  description = "Map of secret names to their ARNs"
  value       = { for k, v in aws_secretsmanager_secret.main : k => v.arn }
}

output "secret_ids" {
  description = "Map of secret names to their IDs"
  value       = { for k, v in aws_secretsmanager_secret.main : k => v.id }
}
