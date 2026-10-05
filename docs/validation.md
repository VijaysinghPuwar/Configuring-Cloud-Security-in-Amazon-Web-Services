# Live validation runbook

The Terraform in this repository has been validated statically (fmt, validate,
mocked `terraform test`, TFLint, Checkov). **None of the steps below have been
run against the Terraform deployment yet.** When they are, record the outcome
in the README results table and add evidence to `screenshots/terraform-lab/`.

Commands assume you are in `terraform/` after `terraform apply`, with the AWS
CLI v2 and the
[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
installed.

```bash
IP=$(terraform output -raw instance_public_ip)
ID=$(terraform output -raw instance_id)
LOG=$(terraform output -raw flow_log_group)
```

## 1. Management path: Session Manager only

```bash
$(terraform output -raw ssm_session_command)   # expect a shell as ssm-user
nc -vz -w 5 "$IP" 22                            # expect timeout: no SSH rule exists
```

## 2. ICMP from the admin machine (`nacl_icmp_mode = "allow"`)

```bash
ping -c 4 "$IP"    # expect 4 replies
```

Path: NACL inbound rule 100 (echo request from admin CIDR), security group
ingress (echo request from admin CIDR), NACL outbound rule 120 (echo reply to
admin CIDR). The security group needs no outbound rule for the reply because
it is stateful; the NACL does because it is not.

## 3. NACL deny for the admin CIDR (`deny_admin`)

```bash
terraform apply -var 'nacl_icmp_mode=deny_admin'
ping -c 4 "$IP"    # expect 100% packet loss
```

Rule 90 (deny ICMP from admin CIDR) is evaluated before rule 100 (allow), so
the echo request is dropped at the subnet boundary before the security group
is consulted.

## 4. Stateless side effect (`deny_all`)

```bash
terraform apply -var 'nacl_icmp_mode=deny_all'
# inside the Session Manager shell:
ping -c 3 8.8.8.8  # expect 100% packet loss
```

The outbound echo request (type 8) is allowed by NACL outbound rule 110, but
the echo reply (type 0) coming back is a separate inbound packet to the NACL
and now matches the rule 90 deny before rule 110 can allow it. A security
group alone would never cause this, because it tracks the outbound flow and
admits the reply.

Set the mode back with `terraform apply -var 'nacl_icmp_mode=allow'`.

## 5. Self-ping of the public IP

```bash
# inside the Session Manager shell, in allow mode, using the instance_public_ip output:
ping -c 3 <instance_public_ip>
```

Expected: no replies. The packet leaves through the internet gateway and comes
back in with the instance's own public IP as the source. That source is not
`trusted_admin_cidr`, so NACL rule 100 and the security group rule do not match.
This is ordinary filtering, not an AWS restriction on hairpinning (see
`docs/original-lab.md`, where the same test succeeded once ICMP was allowed
from `0.0.0.0/0`).

## 6. IMDSv2 enforcement

```bash
# inside the Session Manager shell
curl -s -o /dev/null -w '%{http_code}\n' http://169.254.169.254/latest/meta-data/instance-id
# expect 401: a request without a token is refused

TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id
# expect the instance ID
```

From your workstation:

```bash
aws ec2 describe-instances --instance-ids "$ID" \
  --query 'Reservations[0].Instances[0].MetadataOptions'
# expect "HttpTokens": "required", "HttpPutResponseHopLimit": 1
```

The `MetadataNoToken` metric counts metadata calls that were made without a
token, i.e. IMDSv1 usage. Watching it before switching `http_tokens` to
`required` shows whether anything on the instance still depends on IMDSv1.

## 7. VPC Flow Logs

Records arrive in CloudWatch Logs after the 1-minute aggregation interval plus
delivery delay, so allow several minutes.

CloudWatch Logs Insights (select the flow log group):

```text
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol, action
| filter protocol = 1
| sort @timestamp desc
| limit 50
```

CLI equivalent for rejected ICMP only:

```bash
aws logs filter-log-events --log-group-name "$LOG" \
  --filter-pattern '[version, account, eni, src, dst, srcport, dstport, protocol=1, packets, bytes, start, end, action=REJECT, status]' \
  --query 'events[].message' --output text
```

### Reading a record

The log group uses the default (version 2) format:

```text
version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status
```

**Illustrative example, not captured output.** Documentation addresses
(RFC 5737) and a placeholder account ID are used:

```text
2 111122223333 eni-0abc123def4567890 203.0.113.10 10.20.1.25 0 0 1 4 336 1767225600 1767225660 REJECT OK
```

| Field | Value | Meaning |
|---|---|---|
| srcaddr | `203.0.113.10` | Admin workstation |
| dstaddr | `10.20.1.25` | Instance private IP (flow logs record the private address on the ENI) |
| srcport / dstport | `0` / `0` | ICMP has no ports, so both are 0 |
| protocol | `1` | IANA protocol number for ICMP (6 is TCP, 17 is UDP) |
| action | `REJECT` | Dropped by the NACL or the security group |

Flow logs do not say which control rejected a packet. To attribute a REJECT
to the NACL, change only the NACL mode between tests and compare.

## 8. CPU alarm and SNS

Confirm the subscription first (only if `alarm_email` was set):

```bash
aws sns list-subscriptions-by-topic --topic-arn "$(terraform output -raw alarm_topic_arn)" \
  --query 'Subscriptions[].SubscriptionArn'
# "PendingConfirmation" means the email link has not been clicked yet
```

Test the notification path without load:

```bash
aws cloudwatch set-alarm-state --alarm-name "$(terraform output -raw cpu_alarm_name)" \
  --state-value ALARM --state-reason "manual notification test"
```

Test real metric evaluation (t3.micro has 2 vCPUs):

```bash
# inside the Session Manager shell
for i in 1 2; do timeout 300 yes > /dev/null & done
```

```bash
aws cloudwatch describe-alarm-history --alarm-name "$(terraform output -raw cpu_alarm_name)" \
  --history-item-type StateUpdate --max-items 5
```

T3 instances default to unlimited CPU credits. A five-minute burst costs
little, but long load tests can add surplus credit charges.

## 9. Destroy and confirm cleanup

```bash
terraform destroy
terraform state list          # expect no output

aws ec2 describe-instances --filters "Name=tag:Project,Values=ec2-net-hardening" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId'      # expect []
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=ec2-net-hardening" \
  --query 'Vpcs[].VpcId'                               # expect []
aws logs describe-log-groups --log-group-name-prefix /vpc-flow-logs/ec2-net-hardening \
  --query 'logGroups[].logGroupName'                   # expect []
```

The KMS key is not deleted immediately. It is scheduled for deletion with a
7-day waiting period, which is an AWS safeguard.
