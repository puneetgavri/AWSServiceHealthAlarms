resource "aws_sns_topic" "dynamodb_health_topic" {
  name        = "DynamoDBHealthAlarmTopic"
  display_name = "DynamoDB Health Alarm Notifications"
}

resource "aws_sns_topic_subscription" "dynamodb_health_email" {
  topic_arn = aws_sns_topic.dynamodb_health_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_log_group" "dynamodb_health_log_group" {
  name              = "/aws/events/DynamoDBServiceHealth"
  retention_in_days = 14
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_target_role" {
  name               = "DynamoDBHealthEventTargetRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "put_log_events_policy" {
  name        = "AllowPutLogEventsToDynamoDBHealthLogGroup"
  description = "Allow EventBridge to write logs to DynamoDB Health Log Group"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = aws_cloudwatch_log_group.dynamodb_health_log_group.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy_to_role" {
  role       = aws_iam_role.eventbridge_target_role.name
  policy_arn = aws_iam_policy.put_log_events_policy.arn
}

resource "aws_cloudwatch_event_rule" "dynamodb_health_event_rule" {
  name        = "DynamoDBServiceHealthMonitor"
  description = "Detect AWS Health DynamoDB issues and log them"
  event_pattern = jsonencode({
    "source": ["aws.health"],
    "detail-type": ["AWS Health Event"],
    "detail": {
      "service": ["DynamoDB"],
      "eventTypeCategory": ["issue"],
      "eventTypeCode": [
        "AWS_DYNAMODB_API_ISSUE",
        "AWS_DYNAMODB_OPERATIONAL_ISSUE",
        "AWS_DYNAMODB_INCREASED_READ_LATENCY",
        "AWS_DYNAMODB_INCREASED_WRITE_LATENCY",
        "AWS_DYNAMODB_INCREASED_ERROR_RATES"
      ]
    }
  })
  is_enabled = true
}

resource "aws_cloudwatch_event_target" "dynamodb_health_log_target" {
  rule      = aws_cloudwatch_event_rule.dynamodb_health_event_rule.name
  arn       = aws_cloudwatch_log_group.dynamodb_health_log_group.arn
  role_arn  = aws_iam_role.eventbridge_target_role.arn
  target_id = "DynamoDBHealthLogGroupTarget"
}

resource "aws_cloudwatch_log_metric_filter" "dynamodb_health_metric_filter" {
  name           = "DynamoDBHealthMetricFilter"
  log_group_name = aws_cloudwatch_log_group.dynamodb_health_log_group.name

  pattern = <<PATTERN
{ $.detail.eventTypeCode = "AWS_DYNAMODB_API_ISSUE" || $.detail.eventTypeCode = "AWS_DYNAMODB_OPERATIONAL_ISSUE" || $.detail.eventTypeCode = "AWS_DYNAMODB_INCREASED_READ_LATENCY" || $.detail.eventTypeCode = "AWS_DYNAMODB_INCREASED_WRITE_LATENCY" || $.detail.eventTypeCode = "AWS_DYNAMODB_INCREASED_ERROR_RATES" }
PATTERN

  metric_transformation {
    name      = "DynamoDBHealthOutageCount"
    namespace = "Custom/AWSHealth"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_health_alarm" {
  alarm_name          = "DynamoDBServiceHealthAlarm"
  alarm_description   = "Alarm triggered on DynamoDB Health service issues detected via AWS Health events"
  namespace           = "Custom/AWSHealth"
  metric_name         = aws_cloudwatch_log_metric_filter.dynamodb_health_metric_filter.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions           = [aws_sns_topic.dynamodb_health_topic.arn]
  ok_actions              = [aws_sns_topic.dynamodb_health_topic.arn]
  insufficient_data_actions = [aws_sns_topic.dynamodb_health_topic.arn]
}
