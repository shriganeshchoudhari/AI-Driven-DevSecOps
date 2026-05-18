output "sbom_bucket_name" {
  description = "Name of the bucket storing SBOM files"
  value       = aws_s3_bucket.sbom_archive.id
}
