output "instance_id" {
  description = "ID of the lab instance."
  value       = aws_instance.lab.id
}

output "instance_public_ip" {
  description = "Public IPv4 address used for the ICMP tests."
  value       = aws_instance.lab.public_ip
}

output "vpc_id" {
  description = "ID of the lab VPC."
  value       = aws_vpc.lab.id
}

output "security_group_id" {
  description = "ID of the instance security group."
  value       = aws_security_group.instance.id
}

output "network_acl_id" {
  description = "ID of the subnet network ACL."
  value       = aws_network_acl.public.id
}

output "nacl_icmp_mode" {
  description = "Current inbound ICMP mode of the network ACL."
  value       = var.nacl_icmp_mode
}

output "flow_log_group" {
  description = "CloudWatch Logs group that receives VPC Flow Logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "alarm_topic_arn" {
  description = "SNS topic that receives CPU alarm notifications."
  value       = aws_sns_topic.alarms.arn
}

output "cpu_alarm_name" {
  description = "Name of the CPU utilization alarm."
  value       = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}

output "ssm_session_command" {
  description = "Open a shell on the instance through Session Manager (requires the Session Manager plugin)."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.lab.id}"
}
