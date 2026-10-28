mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name = "demo"
}

run "spreads_subnets_across_zones" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 3 && length(aws_subnet.public) == 3
    error_message = "Expected one public and one private subnet per zone."
  }

  assert {
    condition     = toset(aws_subnet.private[*].availability_zone) == toset(["eu-central-1a", "eu-central-1b", "eu-central-1c"])
    error_message = "Private subnets must land in distinct zones."
  }
}

run "subnet_ranges_do_not_overlap" {
  command = plan

  assert {
    condition = length(distinct(concat(
      aws_subnet.public[*].cidr_block,
      aws_subnet.private[*].cidr_block,
    ))) == 6
    error_message = "Every subnet needs its own CIDR block."
  }

  assert {
    condition     = aws_subnet.private[0].cidr_block == "10.0.128.0/20"
    error_message = "Private subnets start in the upper half of the VPC range."
  }
}

run "tags_subnets_for_load_balancer_discovery" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets need the elb role tag for internet-facing load balancers."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Private subnets need the internal-elb role tag."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/cluster/demo"] == "shared"])
    error_message = "Subnets must be tagged with the cluster name."
  }
}

run "nat_gateway_per_zone_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Each zone should egress through its own NAT gateway."
  }
}

run "single_nat_gateway_routes_every_zone_through_it" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single_nat_gateway should create exactly one NAT gateway."
  }

  assert {
    condition     = length(aws_route_table.private) == 3
    error_message = "Every private subnet still needs a route table."
  }
}

run "rejects_small_vpc" {
  command = plan

  variables {
    cidr = "10.0.0.0/24"
  }

  expect_failures = [var.cidr]
}

run "rejects_single_zone" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}
