variable "root_application_path" {
  description = "Path to the app-of-apps Application manifest that the cluster bootstraps from."
  type        = string
}

variable "namespace" {
  type    = string
  default = "argocd"
}

variable "argocd_chart_version" {
  type    = string
  default = "10.11.6"
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.7"
}
