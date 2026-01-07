variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "me-south-1"
}

variable "bucket_name" {
  description = "The unique name for the S3 bucket"
  type        = string
  # Replace with a unique name or pass via CLI/tfvars
  default     = "noon-course-s3-bucket" 
}

variable "environment" {
  description = "Environment tag (e.g., dev, prod)"
  type        = string
  default     = "dev"
}