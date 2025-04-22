provider "aws" {
  region = var.region
}

# SNS Topic
resource "aws_sns_topic" "stop_ec2_topic" {
  name = "stop-ec2-notification"
}

# SNS Subscription (send email)
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.stop_ec2_topic.arn
  protocol  = "email"
  endpoint  = var.sns_email  # Địa chỉ email nhận thông báo
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_stop_ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_stop_ec2_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions", 
          "ec2:StopInstances"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "sns:Publish"
        ],
        Resource = aws_sns_topic.stop_ec2_topic.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

# Package Lambda Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/sources"
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda Function
resource "aws_lambda_function" "stop_ec2" {
  function_name = "stop-ec2-instances"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)
  timeout       = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.stop_ec2_topic.arn
    }
  }
}

# CloudWatch Event Rule (Trigger mỗi ngày lúc 11:00 UTC = 18:00 VN)
resource "aws_cloudwatch_event_rule" "stop_ec2_schedule" {
  name                = "stop-ec2-everyday-6pm-vietnam"
  schedule_expression = "cron(0 11 * * ? *)" # 11AM UTC ~ 6PM VN
}

# Permission cho Event Rule invoke Lambda
resource "aws_lambda_permission" "allow_event_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_ec2.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_ec2_schedule.arn
}

# CloudWatch Event Target
resource "aws_cloudwatch_event_target" "stop_ec2_target" {
  rule      = aws_cloudwatch_event_rule.stop_ec2_schedule.name
  target_id = "stop-ec2-lambda"
  arn       = aws_lambda_function.stop_ec2.arn
}
