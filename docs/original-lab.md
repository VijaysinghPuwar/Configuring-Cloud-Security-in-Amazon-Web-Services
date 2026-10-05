# Original console lab (April 2025) and corrections

This project started as a course lab built by hand in the AWS console: one
instance in the **default VPC**, the wizard-created `launch-wizard-1`
security group, and the VPC's **default network ACL**. The original write-up
was a 43-page PDF. It has been removed from the repository because several of
its conclusions were wrong and it exposed account details. This page keeps the
evidence that matters and states what it actually shows.

The Terraform in `terraform/` is the rebuilt version. Nothing on this page was
produced by that code.

Account IDs and the instance ARN are redacted in the screenshots. The public
IP shown (`34.227.152.67`) was an ephemeral AWS address that was released when
the instance was terminated.

## Corrections

| Original claim | What the evidence shows |
|---|---|
| Instance ran Amazon Linux 2 | The AMI was `al2023-ami-...` and the login banner says Amazon Linux 2023 ([01](../screenshots/2025-console-lab/01-ssh-login-amazon-linux-2023.png)). |
| AWS does not allow an instance to ping its own public IP | The self-ping failed while the security group allowed only SSH ([02](../screenshots/2025-console-lab/02-sg-original-ssh-open-to-world.png), [03](../screenshots/2025-console-lab/03-self-ping-public-ip-blocked-by-sg.png)) and succeeded as soon as an inbound ICMP rule was added ([04](../screenshots/2025-console-lab/04-sg-icmp-rule-added.png), [05](../screenshots/2025-console-lab/05-self-ping-public-ip-allowed.png)). The packet hairpins through the internet gateway and returns with the public IP as its source, so it needs an inbound rule like any other sender. |
| NACL rule 51 blocked ICMP | Rule 51 was saved as **All traffic / Allow**, not an ICMP deny ([07](../screenshots/2025-console-lab/07-nacl-rule-51-allow-misconfiguration.png)). Rule 1 already allowed all traffic, and NACL evaluation stops at the first matching rule, so nothing after rule 1 could have changed the outcome. Pings kept succeeding ([08](../screenshots/2025-console-lab/08-ping-after-nacl-edit-still-succeeds.png)). No ICMP block was ever demonstrated. |
| "Ping still works because the inbound NACL rule only affects traffic from outside" | NACLs are stateless. If an inbound ICMP deny had been in effect, the echo replies to the instance's own pings would also have been dropped, because each reply is evaluated as new inbound traffic. The ping worked because nothing was denied. |
| An inbound NACL rule alone blocks pings from outside | Correct only if the deny has a lower rule number than every rule that would allow the traffic. Here rule 1 allowed everything. |
| Enabling monitoring installed the CloudWatch agent | Detailed monitoring only changes the basic EC2 metrics from 5-minute to 1-minute periods. The CloudWatch agent is separate software that collects OS-level metrics such as memory and disk; it was never installed. The banner in [09](../screenshots/2025-console-lab/09-imdsv2-required-and-metrics.png) is a console notice about the `CWAgent` namespace, not proof of an agent. |
| "Metadata no token" monitors IMDSv2 security requests | `MetadataNoToken` counts metadata calls made **without** a session token, i.e. IMDSv1 usage. IMDSv2 was already set to Required on this instance and the graph stayed at 0 ([09](../screenshots/2025-console-lab/09-imdsv2-required-and-metrics.png)). |
| CPU alarm configured at 70% | The saved alarm was `CPUUtilization > 10000` for 1 of 1 five-minute datapoints ([10](../screenshots/2025-console-lab/10-cloudwatch-alarm-original-10000-threshold.png)). CPUUtilization is a percentage, so the alarm could never fire. The description text said 70%, but the threshold did not. |
| SNS alerting worked | The subscription was still pending email confirmation, and the alarm never left `OK`. No notification was sent or received. |

## Security issues in the original setup

- SSH was open to `0.0.0.0/0` ([02](../screenshots/2025-console-lab/02-sg-original-ssh-open-to-world.png)).
- ICMP was later opened to `0.0.0.0/0` as well ([04](../screenshots/2025-console-lab/04-sg-icmp-rule-added.png)).
- Everything was in the default VPC with the default NACL shared by six subnets ([06](../screenshots/2025-console-lab/06-default-nacl-inbound-rules.png)), so the NACL edit affected every subnet in the VPC, not just the lab.
- The root volume was unencrypted and no flow logs were enabled.

The Terraform rebuild addresses each of these: no SSH (Session Manager instead),
ICMP limited to one `/32`, a dedicated VPC and subnet NACL, encrypted EBS,
and VPC Flow Logs.

## Other evidence kept

- [11](../screenshots/2025-console-lab/11-outbound-ping-8-8-8-8.png): outbound ping to 8.8.8.8 succeeded with the default "all traffic" egress rule, and the replies came back because the security group is stateful.
