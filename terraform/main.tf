# provider
provider "aws" {
  profile = var.profile
  region  = var.region
}

# s3
resource "aws_s3_bucket" "bucket" {
  bucket = "${var.project}.${var.domain}"
  acl = "private"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Sid": "Cloudfront Read",
          "Effect": "Allow",
          "Principal": {
              "AWS": "${aws_cloudfront_origin_access_identity.oai.iam_arn}"
          },
          "Action": "s3:GetObject",
          "Resource": [
            "arn:aws:s3:::${var.project}.${var.domain}/*"
          ]
      }
  ]
}
EOF
}

resource "aws_s3_bucket_public_access_block" "pab" {
  bucket = aws_s3_bucket.bucket.id
  block_public_acls   = true
  block_public_policy = true
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "${var.project}.${var.domain} identity"
}

locals {
  s3_origin_id = "${var.project}-origin"
}

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["${var.project}.${var.domain}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    trusted_signers = []

    forwarded_values {
      query_string = false
      query_string_cache_keys = []
      headers = []

      cookies {
        forward = "none"
        whitelisted_names = []
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 31536000
  }
  restrictions {
    geo_restriction {
        locations        = []
        restriction_type = "none"
    }
}

  viewer_certificate {
      acm_certificate_arn            = var.certificate_arn
      cloudfront_default_certificate = false
      minimum_protocol_version       = "TLSv1.1_2016"
      ssl_support_method             = "sni-only"
  }
}

resource "aws_route53_record" "record" {
  zone_id = var.zone_id
  name    = "${var.project}.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.distribution.domain_name
    zone_id                = aws_cloudfront_distribution.distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
