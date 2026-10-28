locals {
  name = "hello-dev"

  tags = {
    Project     = "eks-gitops-platform"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  cidr               = "10.20.0.0/16"
  az_count           = 2
  single_nat_gateway = true
}

module "eks" {
  source = "../../modules/eks"

  cluster_name           = local.name
  subnet_ids             = module.network.private_subnet_ids
  endpoint_public_access = true
  public_access_cidrs    = var.public_access_cidrs
  admin_principal_arns   = var.admin_principal_arns
  node_capacity_type     = "SPOT"
  node_instance_types    = ["t3.medium", "t3a.medium"]

  node_scaling = {
    min     = 2
    desired = 2
    max     = 3
  }
}

module "argocd" {
  source = "../../modules/argocd"

  root_application_path = "${path.root}/../../../gitops/bootstrap/root.yaml"

  depends_on = [module.eks]
}
