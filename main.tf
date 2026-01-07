terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  # MIME type mapping for content_type generation
  mime_types = {
    ".html" = "text/html"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".svg"  = "image/svg+xml"
    ".json" = "application/json"
  }
}

# ------------------------------------------------------------------------------
# S3 Bucket Configuration
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "website_bucket" {
  bucket        = var.bucket_name
  force_destroy = true # Allows deletion even if bucket contains objects

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
  }
}

# Explicitly disable "Block Public Access" to allow the public bucket policy
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html" # Often useful for SPAs, or specify error.html
  }
}

# Bucket Policy to allow public read access (Anonymous GetObject)
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.website_bucket.id

  # Ensure public access block is removed before applying policy
  depends_on = [aws_s3_bucket_public_access_block.public_access]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website_bucket.arn}/*"
      },
    ]
  })
}

# ------------------------------------------------------------------------------
# Object Uploads (Dynamic Content-Type)
# ------------------------------------------------------------------------------

# Upload index.html to root
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website_bucket.id
  key          = "index.html"
  source       = "./index.html"
  etag         = filemd5("./index.html")
  content_type = "text/html"
}

# Iterate over ./img folder and upload all files to /img prefix
resource "aws_s3_object" "images" {
  for_each = fileset("./img", "**")

  bucket = aws_s3_bucket.website_bucket.id
  key    = "img/${each.value}"
  source = "./img/${each.value}"
  etag   = filemd5("./img/${each.value}")

  # Dynamic Content-Type lookup based on file extension
  content_type = lookup(
    local.mime_types,
    regex("\\.[^.]+$", each.value),
    "application/octet-stream"
  )
}

# ------------------------------------------------------------------------------
# CloudFront Distribution
# ------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # Use PriceClass_All for global edge locations

  # Origin Configuration: Using S3 Website Endpoint (Custom Origin)
  origin {
    domain_name = aws_s3_bucket_website_configuration.website_config.website_endpoint
    origin_id   = "S3-Website-${var.bucket_name}"

    # Custom Origin Config is required for S3 Website Endpoints (not REST endpoints)
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # S3 Website endpoints only support HTTP
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Website-${var.bucket_name}"

    viewer_protocol_policy = "redirect-to-https"

    # Using CachingOptimized managed policy
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    compress = true
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = var.environment
  }
}