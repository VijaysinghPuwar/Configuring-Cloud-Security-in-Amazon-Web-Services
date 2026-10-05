# Latest Amazon Linux 2023 AMI, resolved from the public SSM parameter so no
# AMI ID is hardcoded. The SSM Agent is preinstalled on this image.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "lab" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  monitoring             = var.enable_detailed_monitoring
  ebs_optimized          = true

  # The lab tests ICMP from the administrator's own machine across the
  # internet, which requires a public address. Exposure is limited by the
  # security group (ICMP echo from trusted_admin_cidr only, no TCP or UDP
  # ingress) and by the network ACL.
  #checkov:skip=CKV_AWS_88:Public IP is required for the internet-facing ICMP test. Ingress is limited to ICMP echo from trusted_admin_cidr.
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # token cannot be used from a container or forwarded hop
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.project_name}-instance" }

  lifecycle {
    # A newer AMI being published should not replace a running lab instance.
    ignore_changes = [ami]
  }
}
