variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other prod layer."
  type        = string
  default     = "eu-central-1"
}
