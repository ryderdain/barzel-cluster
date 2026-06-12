variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other dev layer."
  type        = string
  default     = "eu-central-1"
}
