output "dynamodb_health_alarm_name" {
  description = "The CloudWatch alarm for DynamoDB Health events"
  value       = aws_cloudwatch_metric_alarm.dynamodb_health_alarm.alarm_name
}

output "dynamodb_health_sns_topic_arn" {
  description = "SNS Topic ARN for DynamoDB Health notifications"
  value       = aws_sns_topic.dynamodb_health_topic.arn
}

output "notification_email_confirm" {
  description = "subscription email for receiving notifications"
  value       = var.notification_email
}
