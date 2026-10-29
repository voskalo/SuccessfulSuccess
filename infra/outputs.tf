output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "issuer" {
  value = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "hosted_domain" {
  value = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "google_redirect_uri" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"
}

output "google_enabled" {
  value = var.google_client_id == "" ? "false" : "true"
}

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "reports_queue_url" {
  value = aws_sqs_queue.report_requests.url
}

output "parser_url" {
  value = aws_lambda_function_url.parser.function_url
}

output "parser_function_name" {
  value = aws_lambda_function.parser.function_name
}

output "parser_log_group" {
  value = aws_cloudwatch_log_group.parser.name
}
