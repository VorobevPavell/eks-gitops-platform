variable "name" {
  description = "Prefix for resource names; also the EKS cluster name used in subnet discovery tags."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block; split into /20 subnets, public first, private after."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) <= 16
    error_message = "cidr must be a valid IPv4 block of /16 or larger."
  }
}

variable "az_count" {
  description = "How many availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "EKS needs subnets in at least two zones; four is the most this layout supports."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway instead of one per zone: cheaper, but a zone outage cuts egress for all."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
