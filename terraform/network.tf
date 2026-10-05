resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# Every VPC gets a default security group that allows all traffic between its
# members. Taking ownership of it with no rules leaves it empty, so nothing can
# accidentally fall back to it.
resource "aws_default_security_group" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = { Name = "${var.project_name}-default-sg-unused" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Network ACL (stateless, subnet level)
#
# Rules are evaluated in ascending rule-number order and evaluation stops at
# the first match. Return traffic is NOT tracked, so every reply needs its own
# rule in the opposite direction.
#
# Traffic to the Amazon DNS resolver, the instance metadata service and the
# Amazon Time Sync Service is not filtered by network ACLs, so no rules are
# needed for those.
# ---------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.lab.id
  subnet_ids = [aws_subnet.public.id]

  tags = { Name = "${var.project_name}-public-nacl" }
}

locals {
  icmp_echo_reply   = 0
  icmp_echo_request = 8

  # Linux ephemeral port range (net.ipv4.ip_local_port_range on Amazon Linux 2023
  # is 32768-60999). Replies to the instance's outbound HTTPS land here.
  ephemeral_from = 32768
  ephemeral_to   = 65535

  icmp_deny_source = {
    allow      = null
    deny_admin = var.trusted_admin_cidr
    deny_all   = "0.0.0.0/0"
  }[var.nacl_icmp_mode]
}

# Rule 90 is evaluated before the allow rules at 100 and 110. Placing the deny
# at a lower number than the allows is what makes it effective.
resource "aws_network_acl_rule" "in_deny_icmp" {
  #checkov:skip=CKV_AWS_352:ICMP has no ports. The check only passes rules with a from_port, so every ICMP rule fails it. Source is limited by cidr_block and ICMP type.
  count = local.icmp_deny_source == null ? 0 : 1

  network_acl_id = aws_network_acl.public.id
  egress         = false
  rule_number    = 90
  rule_action    = "deny"
  protocol       = "icmp"
  icmp_type      = -1
  icmp_code      = -1
  cidr_block     = local.icmp_deny_source
}

resource "aws_network_acl_rule" "in_admin_echo_request" {
  #checkov:skip=CKV_AWS_352:ICMP has no ports. The check only passes rules with a from_port, so every ICMP rule fails it. Source is limited by cidr_block and ICMP type.
  network_acl_id = aws_network_acl.public.id
  egress         = false
  rule_number    = 100
  rule_action    = "allow"
  protocol       = "icmp"
  icmp_type      = local.icmp_echo_request
  icmp_code      = -1
  cidr_block     = var.trusted_admin_cidr
}

# Replies to pings the instance sends out. Without this rule, an outbound
# "ping 8.8.8.8" fails even though the outbound request is allowed.
resource "aws_network_acl_rule" "in_echo_reply" {
  #checkov:skip=CKV_AWS_352:ICMP has no ports. The check only passes rules with a from_port, so every ICMP rule fails it. Source is limited by cidr_block and ICMP type.
  network_acl_id = aws_network_acl.public.id
  egress         = false
  rule_number    = 110
  rule_action    = "allow"
  protocol       = "icmp"
  icmp_type      = local.icmp_echo_reply
  icmp_code      = -1
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "in_tcp_return" {
  network_acl_id = aws_network_acl.public.id
  egress         = false
  rule_number    = 120
  rule_action    = "allow"
  protocol       = "tcp"
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "out_https" {
  network_acl_id = aws_network_acl.public.id
  egress         = true
  rule_number    = 100
  rule_action    = "allow"
  protocol       = "tcp"
  from_port      = 443
  to_port        = 443
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "out_echo_request" {
  network_acl_id = aws_network_acl.public.id
  egress         = true
  rule_number    = 110
  rule_action    = "allow"
  protocol       = "icmp"
  icmp_type      = local.icmp_echo_request
  icmp_code      = -1
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "out_admin_echo_reply" {
  network_acl_id = aws_network_acl.public.id
  egress         = true
  rule_number    = 120
  rule_action    = "allow"
  protocol       = "icmp"
  icmp_type      = local.icmp_echo_reply
  icmp_code      = -1
  cidr_block     = var.trusted_admin_cidr
}
