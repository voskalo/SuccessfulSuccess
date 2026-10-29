data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_route_tables" "default" {
  vpc_id = data.aws_vpc.default.id
}

# Created by infra/backend.yml, which stays CloudFormation: the security group
# with access to the database.
data "aws_security_group" "function" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-function"]
  }
}

# Created by infra/backend.yml, which stays CloudFormation.
data "aws_db_instance" "database" {
  db_instance_identifier = "${var.project_name}-db"
}
