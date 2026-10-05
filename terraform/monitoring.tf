locals {
  flow_log_group_name = "/vpc-flow-logs/${var.project_name}"
}

# ---------------------------------------------------------------------------
# Customer managed KMS key for the flow log group and the alarm topic.
#
# A customer managed key is required for the SNS topic: CloudWatch alarms can
# only publish to an encrypted topic if the key policy lets the CloudWatch
# service principal use the key, and the policy of the AWS managed aws/sns key
# cannot be edited.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  # In a key policy, Resource "*" means "this key" and nothing else. The first
  # statement is the AWS default key policy statement that lets IAM policies in
  # this account manage the key; removing it can make the key unmanageable.
  #checkov:skip=CKV_AWS_109:Key policy. Resource "*" is scoped to this key; root statement is the AWS default.
  #checkov:skip=CKV_AWS_111:Key policy. Resource "*" is scoped to this key; service statements are constrained by principal and encryption context.
  #checkov:skip=CKV_AWS_356:Key policy. Resource "*" is the only valid value and refers to this key.
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogsFlowLogGroup"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:${local.flow_log_group_name}"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsPublishToEncryptedTopic"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "monitoring" {
  description             = "${var.project_name} flow logs and alarm notifications"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "monitoring" {
  name          = "alias/${var.project_name}-monitoring"
  target_key_id = aws_kms_key.monitoring.key_id
}

# ---------------------------------------------------------------------------
# VPC Flow Logs -> CloudWatch Logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = local.flow_log_group_name
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = aws_kms_key.monitoring.arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    # Confused-deputy protection: only flow logs in this account can assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:ec2:${var.aws_region}:${local.account_id}:vpc-flow-log/*"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.project_name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

# Write access to this one log group only. CreateLogGroup is omitted because
# Terraform creates the group.
data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }

  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-log-group"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.lab.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = { Name = "${var.project_name}-vpc-flow-log" }
}

# ---------------------------------------------------------------------------
# CPU alarm -> SNS
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name              = "${var.project_name}-alarms"
  kms_master_key_id = aws_kms_key.monitoring.arn
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CPUUtilization is a percentage. With detailed monitoring the metric arrives
# every minute, so "2 of 3 one-minute datapoints above 70%" fires after a
# sustained spike of about two minutes rather than on a single sample.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  alarm_description   = "CPUUtilization above ${var.cpu_alarm_threshold}% for 2 of 3 datapoints on ${aws_instance.lab.id}"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = var.enable_detailed_monitoring ? 60 : 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = aws_instance.lab.id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
