# Offline unit tests. The AWS provider is mocked, so these run without
# credentials and create nothing. They prove the configuration produces the
# intended controls; they do not prove AWS enforces them (see docs/validation.md).

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_ec2_instance_type_offerings" {
    defaults = {
      locations = ["us-east-1b", "us-east-1a"]
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  trusted_admin_cidr = "203.0.113.10/32"
}

run "imdsv2_and_instance_hardening" {
  command = plan

  assert {
    condition     = aws_instance.lab.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }

  assert {
    condition     = aws_instance.lab.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDS hop limit must be 1."
  }

  assert {
    condition     = aws_instance.lab.root_block_device[0].encrypted == true
    error_message = "Root volume must be encrypted."
  }

  assert {
    condition     = aws_subnet.public.availability_zone == "us-east-1a"
    error_message = "AZ should be the first AZ (sorted) that offers the instance type."
  }
}

run "security_group_has_no_tcp_ingress" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.admin_echo_request.ip_protocol == "icmp"
    error_message = "The only ingress rule must be ICMP."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.admin_echo_request.from_port == 8
    error_message = "Ingress ICMP must be limited to echo request (type 8)."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.admin_echo_request.cidr_ipv4 == var.trusted_admin_cidr
    error_message = "ICMP ingress must come from trusted_admin_cidr only."
  }
}

run "nacl_allow_mode_has_no_deny_rule" {
  command = plan

  assert {
    condition     = length(aws_network_acl_rule.in_deny_icmp) == 0
    error_message = "allow mode must not create the ICMP deny rule."
  }
}

run "nacl_deny_admin_mode" {
  command = plan

  variables {
    nacl_icmp_mode = "deny_admin"
  }

  assert {
    condition     = aws_network_acl_rule.in_deny_icmp[0].rule_action == "deny" && aws_network_acl_rule.in_deny_icmp[0].cidr_block == var.trusted_admin_cidr
    error_message = "deny_admin must deny ICMP from trusted_admin_cidr."
  }

  assert {
    condition     = aws_network_acl_rule.in_deny_icmp[0].rule_number < aws_network_acl_rule.in_admin_echo_request.rule_number
    error_message = "The deny rule must have a lower number than the allow rule, or it never matches."
  }
}

run "nacl_deny_all_mode" {
  command = plan

  variables {
    nacl_icmp_mode = "deny_all"
  }

  assert {
    condition     = aws_network_acl_rule.in_deny_icmp[0].cidr_block == "0.0.0.0/0"
    error_message = "deny_all must deny ICMP from every source."
  }

  assert {
    condition     = aws_network_acl_rule.in_deny_icmp[0].rule_number < aws_network_acl_rule.in_echo_reply.rule_number
    error_message = "deny_all must also shadow the echo-reply allow rule."
  }
}

run "cpu_alarm_uses_percentage_threshold" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high.threshold == 70
    error_message = "Default CPU threshold must be 70 percent."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high.period == 60 && aws_cloudwatch_metric_alarm.cpu_high.datapoints_to_alarm == 2 && aws_cloudwatch_metric_alarm.cpu_high.evaluation_periods == 3
    error_message = "Alarm must be 2 of 3 one-minute datapoints when detailed monitoring is on."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No email subscription should be created unless alarm_email is set."
  }
}

run "alarm_period_without_detailed_monitoring" {
  command = plan

  variables {
    enable_detailed_monitoring = false
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high.period == 300
    error_message = "Basic monitoring publishes 5-minute datapoints, so the period must be 300."
  }
}

run "flow_logs_capture_all_traffic" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc.traffic_type == "ALL" && aws_flow_log.vpc.max_aggregation_interval == 60
    error_message = "Flow logs must capture ACCEPT and REJECT at 1-minute aggregation."
  }
}

run "rejects_open_admin_cidr" {
  command = plan

  variables {
    trusted_admin_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.trusted_admin_cidr]
}

run "rejects_alarm_threshold_above_100" {
  command = plan

  variables {
    cpu_alarm_threshold = 10000
  }

  expect_failures = [var.cpu_alarm_threshold]
}
