# The agenda parser (was infra/ai.yml, Lab 6). Outside the VPC, public function
# URL, Cognito token checked in the handler.

resource "aws_iam_role" "parser" {
  # The name CloudFormation generated. Changing it would replace the role.
  name = "successfulsuccess-ai-ParserRole-D4vWNqq69cxP"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "parser_logs" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser_bedrock" {
  name = "BedrockInference"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "bedrock:InvokeModel"
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = 14
}

resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "Parses pasted text into a suggested agenda with Claude on Bedrock"
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = [var.architecture]
  role          = aws_iam_role.parser.arn
  memory_size   = 512
  timeout       = 30

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.parser.name
  }

  # No VPC block: the parser needs no database.
  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      COGNITO_REGION       = var.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      LOG_LEVEL            = "INFO"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.parser_logs]
}

resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"

  cors {
    allow_origins = var.cors_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }
}

# A public URL needs both permissions (as the API's URL in Lab 4).
resource "aws_lambda_permission" "parser_url" {
  statement_id           = "successfulsuccess-ai-ParserUrlPermission-PVgdRq0yyLsu"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.parser.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_url_invoke" {
  statement_id             = "successfulsuccess-ai-ParserUrlInvokePermission-cYzvIsl9FY6u"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.parser.function_name
  principal                = "*"
  invoked_via_function_url = true
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email != "" ? var.budget_email : var.ses_email]
  }
}
