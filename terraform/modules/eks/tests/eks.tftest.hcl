mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  cluster_name = "demo"
  subnet_ids   = ["subnet-a", "subnet-b", "subnet-c"]
}

run "control_plane_is_hardened" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access
    error_message = "Nodes must reach the API server over the private endpoint."
  }

  assert {
    condition     = !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "The API endpoint is private unless a caller opts in."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "Use EKS access entries instead of the aws-auth ConfigMap."
  }

  assert {
    condition     = !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "Cluster admins are granted explicitly, not by whoever ran apply."
  }

  assert {
    condition     = contains(aws_eks_cluster.this.encryption_config[0].resources, "secrets")
    error_message = "Kubernetes secrets must be envelope-encrypted with KMS."
  }

  assert {
    condition     = contains(aws_eks_cluster.this.enabled_cluster_log_types, "audit")
    error_message = "Audit logs must be shipped to CloudWatch."
  }
}

run "public_endpoint_is_restricted" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["203.0.113.0/24"]
  }

  assert {
    condition     = toset(aws_eks_cluster.this.vpc_config[0].public_access_cidrs) == toset(["203.0.113.0/24"])
    error_message = "Public endpoint must only accept the listed networks."
  }
}

run "rejects_api_open_to_internet" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "rejects_public_endpoint_without_allowed_networks" {
  command = plan

  variables {
    endpoint_public_access = true
  }

  expect_failures = [var.public_access_cidrs]
}

run "networking_addons_install_before_nodes" {
  command = plan

  assert {
    condition     = toset(keys(aws_eks_addon.before_nodes)) == toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])
    error_message = "Nodes cannot become Ready without the CNI, so it must exist first."
  }

  assert {
    condition     = toset(keys(aws_eks_addon.after_nodes)) == toset(["coredns", "metrics-server"])
    error_message = "Workload add-ons need nodes to schedule on."
  }
}

run "nodes_roll_one_at_a_time" {
  command = plan

  assert {
    condition     = aws_eks_node_group.default.update_config[0].max_unavailable == 1
    error_message = "Node group upgrades should replace one node at a time."
  }

  assert {
    condition     = toset(aws_eks_node_group.default.subnet_ids) == toset(["subnet-a", "subnet-b", "subnet-c"])
    error_message = "Nodes belong in the private subnets passed in."
  }
}

run "admins_get_access_entries" {
  command = plan

  variables {
    admin_principal_arns = [
      "arn:aws:iam::111122223333:role/platform-admin",
      "arn:aws:iam::111122223333:role/ci-deployer",
    ]
  }

  assert {
    condition     = length(aws_eks_access_policy_association.admin) == 2
    error_message = "Every admin principal needs a cluster-admin policy association."
  }
}

run "rejects_inverted_scaling" {
  command = plan

  variables {
    node_scaling = {
      min     = 3
      desired = 2
      max     = 4
    }
  }

  expect_failures = [var.node_scaling]
}
