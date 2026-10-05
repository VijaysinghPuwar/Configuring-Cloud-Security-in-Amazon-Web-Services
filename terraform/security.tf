# ---------------------------------------------------------------------------
# Security group (stateful, instance level)
#
# There is no SSH rule. The instance is administered through AWS Systems
# Manager Session Manager, which works over an outbound HTTPS connection that
# the SSM Agent opens, so no inbound management port is exposed.
#
# Because security groups track connection state, replies to allowed traffic
# are permitted automatically in both directions. Only new flows need rules.
# ---------------------------------------------------------------------------

resource "aws_security_group" "instance" {
  name        = "${var.project_name}-instance"
  description = "Lab instance: ICMP echo from the admin CIDR, HTTPS and ICMP echo outbound"
  vpc_id      = aws_vpc.lab.id

  tags = { Name = "${var.project_name}-instance-sg" }
}

# For ICMP rules, from_port is the ICMP type and to_port is the ICMP code.
resource "aws_vpc_security_group_ingress_rule" "admin_echo_request" {
  security_group_id = aws_security_group.instance.id
  description       = "ICMP echo request (type 8) from the trusted admin CIDR"
  ip_protocol       = "icmp"
  from_port         = 8
  to_port           = -1
  cidr_ipv4         = var.trusted_admin_cidr
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTPS to SSM endpoints and Amazon Linux package repositories"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "echo_request" {
  security_group_id = aws_security_group.instance.id
  description       = "ICMP echo request (type 8) for outbound connectivity tests"
  ip_protocol       = "icmp"
  from_port         = 8
  to_port           = -1
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Instance role for Session Manager
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.project_name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# AWS managed policy scoped to what the SSM Agent needs to register the
# instance and carry Session Manager traffic. It grants no S3, EC2 or IAM
# access.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-instance"
  role = aws_iam_role.instance.name
}
