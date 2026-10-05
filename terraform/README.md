# Terraform

Single root module. No remote backend is configured, so state is local and
git-ignored. Add an S3 backend before using this anywhere shared.

| File | Contents |
|---|---|
| `versions.tf` | Terraform and AWS provider constraints |
| `providers.tf` | Provider, default tags, account/partition/AZ lookups |
| `network.tf` | VPC, default SG lockdown, subnet, IGW, route table, network ACL and rules |
| `security.tf` | Instance security group, Session Manager instance role |
| `compute.tf` | Amazon Linux 2023 instance with IMDSv2 and encrypted root volume |
| `monitoring.tf` | KMS key, VPC Flow Logs to CloudWatch Logs, SNS topic, CPU alarm |
| `tests/` | `terraform test` suite against a mocked AWS provider |

## Inputs

| Name | Default | Notes |
|---|---|---|
| `trusted_admin_cidr` | none (required) | Your public IP as `/32`. `0.0.0.0/0` is rejected by validation. |
| `aws_region` | `us-east-1` | |
| `project_name` | `ec2-net-hardening` | Prefix for names and the `Project` tag |
| `instance_type` | `t3.micro` | Must be x86_64 |
| `nacl_icmp_mode` | `allow` | `allow`, `deny_admin` or `deny_all` |
| `enable_detailed_monitoring` | `true` | 1-minute metrics; alarm period follows this setting |
| `cpu_alarm_threshold` | `70` | Percent, 1 to 100 |
| `alarm_email` | `null` | Optional, sensitive. Requires clicking the AWS confirmation email. |
| `flow_log_retention_days` | `365` | Log group is deleted on destroy regardless |
| `vpc_cidr` / `public_subnet_cidr` | `10.20.0.0/16` / `10.20.1.0/24` | |
| `availability_zone` | `null` | Null picks the first AZ that offers `instance_type` |

## Outputs

`instance_id`, `instance_public_ip`, `vpc_id`, `security_group_id`,
`network_acl_id`, `nacl_icmp_mode`, `flow_log_group`, `alarm_topic_arn`,
`cpu_alarm_name`, `ssm_session_command`.

## Local checks

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test                 # mocked provider, no credentials needed
tflint --init && tflint
checkov -d . --framework terraform
```

## Checkov skips

Every skip is an inline `#checkov:skip` comment next to the resource, with the
reason. There are three:

| Check | Resource | Why |
|---|---|---|
| CKV_AWS_88 (public IP) | `aws_instance.lab` | The lab tests ICMP across the internet from the admin machine. Ingress is ICMP echo from one `/32` only. |
| CKV_AWS_109, 111, 356 (`Resource "*"`) | `aws_iam_policy_document.kms` | This is a KMS key policy. In a key policy `"*"` means the key itself. The root statement is the AWS default that keeps the key manageable through IAM. |
| CKV_AWS_352 (NACL ingress without ports) | three ICMP NACL rules | ICMP has no ports. The check passes only rules with a `from_port`, so every ICMP rule fails, including the deny rule. |

## Findings fixed rather than skipped

| Check | Fix |
|---|---|
| CKV_AWS_394 (unpinned AZ data source) | Replaced `aws_availability_zones` with `aws_ec2_instance_type_offerings`, which also prevents launching into an AZ that has no capacity for the chosen type. |

Controls that Checkov verifies and that were designed in from the start:
IMDSv2 required, EBS encryption, EBS optimisation, detailed monitoring, instance
IAM role, VPC flow logs, default security group with no rules, log group KMS
encryption and retention, SNS topic KMS encryption, KMS key rotation.
