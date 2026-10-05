variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix applied to every resource."
  type        = string
  default     = "ec2-net-hardening"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project_name))
    error_message = "project_name must be 3-32 characters of lowercase letters, digits and hyphens."
  }
}

variable "trusted_admin_cidr" {
  description = "The only source allowed to send ICMP echo requests to the instance, normally YOUR_PUBLIC_IP/32."
  type        = string

  validation {
    condition     = can(cidrhost(var.trusted_admin_cidr, 0)) && !startswith(var.trusted_admin_cidr, "0.0.0.0/")
    error_message = "trusted_admin_cidr must be a valid IPv4 CIDR and must not be 0.0.0.0/0."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet. Must sit inside vpc_cidr."
  type        = string
  default     = "10.20.1.0/24"
}

variable "availability_zone" {
  description = "Availability Zone for the subnet. Null selects the first available AZ."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type. Must be x86_64 to match the Amazon Linux 2023 AMI parameter."
  type        = string
  default     = "t3.micro"
}

variable "nacl_icmp_mode" {
  description = <<-EOT
    Inbound ICMP behaviour of the subnet Network ACL:
      allow      - echo requests from trusted_admin_cidr and echo replies from anywhere are allowed
      deny_admin - rule 90 denies all ICMP from trusted_admin_cidr before the allow rules are evaluated
      deny_all   - rule 90 denies all inbound ICMP, which also breaks replies to pings the instance sends
  EOT
  type        = string
  default     = "allow"

  validation {
    condition     = contains(["allow", "deny_admin", "deny_all"], var.nacl_icmp_mode)
    error_message = "nacl_icmp_mode must be one of: allow, deny_admin, deny_all."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 detailed monitoring (1-minute metrics). Adds a small hourly charge."
  type        = bool
  default     = true
}

variable "cpu_alarm_threshold" {
  description = "CPUUtilization percentage that triggers the alarm."
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold is a percentage and must be between 1 and 100."
  }
}

variable "alarm_email" {
  description = "Optional email address subscribed to the alarm topic. Leave null to skip. AWS sends a confirmation email that must be accepted."
  type        = string
  default     = null
  sensitive   = true
}

variable "flow_log_retention_days" {
  description = "Retention period for the VPC Flow Log group."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a value CloudWatch Logs accepts."
  }
}
