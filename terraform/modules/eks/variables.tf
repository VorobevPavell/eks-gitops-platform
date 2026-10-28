variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs and worker nodes."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "endpoint_public_access" {
  description = "Expose the API server endpoint publicly (restricted by public_access_cidrs)."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "Networks allowed to reach the public API endpoint, e.g. the office or VPN egress."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "Do not open the API server to the whole internet; list the networks that need it."
  }

  validation {
    condition     = !var.endpoint_public_access || length(var.public_access_cidrs) > 0
    error_message = "A public API endpoint needs at least one allowed network in public_access_cidrs."
  }
}

variable "admin_principal_arns" {
  description = "IAM roles or users that get cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_scaling" {
  type = object({
    min     = number
    desired = number
    max     = number
  })
  default = {
    min     = 2
    desired = 2
    max     = 4
  }

  validation {
    condition     = var.node_scaling.min <= var.node_scaling.desired && var.node_scaling.desired <= var.node_scaling.max
    error_message = "node_scaling must satisfy min <= desired <= max."
  }
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
