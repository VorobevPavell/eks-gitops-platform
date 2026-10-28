mock_provider "helm" {}

variables {
  root_application_path = "../../../gitops/bootstrap/root.yaml"
}

run "installs_pinned_argocd" {
  command = plan

  assert {
    condition     = helm_release.argocd.version == "10.11.6" && helm_release.argocd.atomic
    error_message = "Argo CD chart must be pinned and installed atomically."
  }
}

run "child_applications_report_health_so_sync_waves_wait" {
  command = plan

  assert {
    condition     = strcontains(yamldecode(helm_release.argocd.values[0]).configs.cm["resource.customizations.health.argoproj.io_Application"], "obj.status.health.status")
    error_message = "Without an Application health check, sync waves between child apps do not wait."
  }
}

run "bootstraps_root_app_from_the_repo_manifest" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.source.path == "gitops/apps"
    error_message = "The root application must point at gitops/apps, as in gitops/bootstrap/root.yaml."
  }

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.syncPolicy.automated.selfHeal
    error_message = "The root application must self-heal drift."
  }

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.namespace == "argocd"
    error_message = "Application objects live in the Argo CD namespace."
  }
}
