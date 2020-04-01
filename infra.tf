terraform {
  backend "s3" {}
}

provider "aws" {
  alias  = "acm"
  region = "us-east-1"
}

resource "aws_route53_zone" "zone" {
  name    = "doihavewindows.com."
  comment = "https://github.com/carlosonunez/doihavewindows.com"
}

resource "random_string" "bucket" {
  length  = 8
  upper   = false
  special = false
}

resource "aws_s3_bucket" "website" {
  bucket = "${random_string.bucket.result}-website-bucket-for-doihavewindows.com"
  acl    = "private"
}

resource "aws_acm_certificate" "cert" {
  provider          = aws.acm
  domain_name       = "doihavewindows.com"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  provider = aws.acm
  name     = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_name}"
  type     = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_type}"
  zone_id  = "${aws_route53_zone.zone.id}"
  records  = ["${aws_acm_certificate.cert.domain_validation_options.0.resource_record_value}"]
  ttl      = 60
}


resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.acm
  certificate_arn         = "${aws_acm_certificate.cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.fqdn}"]
}

resource "aws_cloudfront_origin_access_identity" "default" {}

resource "aws_s3_bucket_object" "website" {
  for_each = {
    "index.html"  = "index.html"
    "favicon.ico" = "favicon.ico"
  }
  bucket       = aws_s3_bucket.website.id
  key          = each.value
  source       = "./${each.key}"
  etag         = filemd5("./${each.key}")
  acl          = "public-read"
  content_type = each.key == "website.html" ? "text/html" : "application/pdf"
}

resource "aws_route53_record" "website" {
  depends_on = [aws_s3_bucket_object.website]
  zone_id    = aws_route53_zone.zone.id
  name       = "@"
  type       = "A"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "website_alias" {
  depends_on = [aws_s3_bucket_object.website]
  zone_id    = aws_route53_zone.zone.id
  name       = "www"
  type       = "CNAME"
  ttl        = 1
  records    = ["doihavewindows.com"]
}

resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "website_bucket"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.default.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["doihavewindows.com"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "website_bucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    minimum_protocol_version = "TLSv1"
    ssl_support_method       = "sni-only"
  }
}
