provider "aws" {
  region = "us-east-1" # Adjust based on region
}
# KMS Key for encryption
resource "aws_kms_key" "energy_monitor_key" {
  description = "KMS key for energy monitoring solution"
  enable_key_rotation = true
}

# S3 Bucket for data storage
resource "aws_s3_bucket" "energy_data_bucket" {
  bucket = "energy-monitoring-data-${random_id.suffix.hex}"
  tags = {
    Name = "EnergyMonitoringBucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "energy_data_encryption" {
  bucket = aws_s3_bucket.energy_data_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.energy_monitor_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Random suffix for unique naming
resource "random_id" "suffix" {
  byte_length = 4
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_energy_monitor_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "kinesis:PutRecord"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "energy_processor" {
  filename      = "lambda_function.zip" # Zip your Python code (see below)
  function_name = "energyProcessor"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 10
}

# IoT Rule to trigger Lambda
resource "aws_iot_topic_rule" "energy_rule" {
  name        = "energy_to_lambda"
  enabled     = true
  sql         = "SELECT * FROM 'energy/monitor'"
  sql_version = "2016-03-23"
  lambda {
    function_arn = aws_lambda_function.energy_processor.arn
  }
}

# Kinesis Firehose for batching and S3 delivery
resource "aws_kinesis_firehose_delivery_stream" "energy_stream" {
  name        = "energy-firehose-stream"
  destination = "s3"
  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.energy_data_bucket.arn
    buffer_size = 5   # MB
    buffer_interval = 60 # Seconds
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose_energy_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_policy" {
  role = aws_iam_role.firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${aws_s3_bucket.energy_data_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = "kms:Decrypt"
        Resource = aws_kms_key.energy_monitor_key.arn
      }
    ]
  })
}

# Glue Crawler for cataloging
resource "aws_glue_crawler" "energy_crawler" {
  database_name = aws_glue_catalog_database.energy_db.name
  name          = "energy-crawler"
  role          = aws_iam_role.glue_role.arn
  s3_target {
    path = "s3://${aws_s3_bucket.energy_data_bucket.bucket}"
  }
}

resource "aws_glue_catalog_database" "energy_db" {
  name = "energy_monitoring_db"
}

resource "aws_iam_role" "glue_role" {
  name = "glue_energy_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "glue_policy" {
  role = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = ["${aws_s3_bucket.energy_data_bucket.arn}", "${aws_s3_bucket.energy_data_bucket.arn}/*"]
      }
    ]
  })
}