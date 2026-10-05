provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Pick an Availability Zone that actually offers the chosen instance type.
# Not every AZ does (for example, us-east-1e has no t3 capacity), and letting
# AWS choose can fail at apply time.
data "aws_ec2_instance_type_offerings" "in_az" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  az         = coalesce(var.availability_zone, sort(data.aws_ec2_instance_type_offerings.in_az.locations)[0])
}
