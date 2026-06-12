output "bucket_arn" {
  description = "ARN of the backup bucket (for the node role's S3 grant)."
  value       = aws_s3_bucket.this.arn
}

output "bucket_name" {
  description = "Name of the backup bucket (CNPG barmanObjectStore destinationPath)."
  value       = aws_s3_bucket.this.id
}
