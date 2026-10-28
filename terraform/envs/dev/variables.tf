variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "public_access_cidrs" {
  description = "Networks allowed to reach the public Kubernetes API endpoint."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "IAM roles that get cluster-admin. Must include the role that runs terraform apply: the Helm provider uses it to install Argo CD."
  type        = list(string)
}
