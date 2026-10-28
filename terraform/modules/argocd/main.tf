locals {
  root = yamldecode(file(var.root_application_path))
  root_app = merge(local.root.spec, {
    namespace  = local.root.metadata.namespace
    finalizers = local.root.metadata.finalizers
  })
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  atomic           = true
  timeout          = 600

  values = [yamlencode({
    crds = { keep = true }
    configs = {
      params = { "server.insecure" = true }
      cm = {
        "resource.customizations.health.argoproj.io_Application" = file("${path.module}/application-health.lua")
      }
    }
    dex = { enabled = false }
  })]
}

resource "helm_release" "root" {
  name       = "argocd-root"
  namespace  = var.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = { (local.root.metadata.name) = local.root_app }
  })]

  depends_on = [helm_release.argocd]
}
