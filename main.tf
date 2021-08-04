provider "aws" {
  region = "eu-central-1"
}

provider "null" {
}

provider "local" {
}


resource "aws_cloudfront_origin_access_identity" "identity" {}

resource "aws_s3_bucket" "bucket" {
  bucket        = "spet-test-bucket"
  force_destroy = true
  acl           = "private"
}

data "aws_iam_policy_document" "bucket-policy" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "${aws_s3_bucket.bucket.arn}/*",
      aws_s3_bucket.bucket.arn
    ]
    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.identity.iam_arn
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket-policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.bucket-policy.json
}


locals {
  s3_origin_id = "s3-client-bucket"
}

resource "aws_cloudfront_distribution" "main" {
  default_root_object = "index.html"
  enabled             = true
  is_ipv6_enabled     = true

  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.identity.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD"
    ]
    cached_methods = [
      "GET",
      "HEAD"
    ]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "null_resource" "upload" {
  triggers = {
    build_number = timestamp()
  }

  provisioner "local-exec" {
    working_dir = "."
    command     = "aws s3 cp ./html/ s3://${aws_s3_bucket.bucket.bucket} --recursive --metadata-directive REPLACE --expires 2025-01-01T00:00:00Z --cache-control max-age=2592000,public"
  }
}

output "url" {
  value = "https://${aws_cloudfront_distribution.main.domain_name}/"
}