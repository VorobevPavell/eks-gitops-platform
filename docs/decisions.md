# Design decisions

Short records of the choices in this repository and what they cost.

## 1. Deploy by commit, not by `kubectl` or an image updater

CI never talks to the cluster. The `app` workflow builds an image and commits the new tag to
`gitops/envs/dev/values.yaml`; Argo CD applies it. The cluster state is whatever `main` says, every
deploy has an author and a diff, and the CI token needs no cluster credentials.

Argo CD Image Updater would remove the commit step, but the deploy would then live in a controller's
memory and annotations instead of in history. One commit per deploy keeps rollback to `git revert`.

## 2. Prod follows its own branch; promotion moves it

`hello-dev` tracks `main`, `hello-prod` tracks the `prod` branch. `promote` takes the commit dev is
synced to, sets the prod image tag to the one dev ran at that commit, and fast-forwards `prod`. It
refuses when `main` has changed `charts/` or the prod values after that commit, before and again
after writing the tag, so a chart change or a newer image cannot ride along into prod untested.

The gate holds when two settings exist (README, "Repository setup"): the `prod` environment with
required reviewers, and a ruleset that lets only the promote workflow move the `prod` branch. Until
the first promotion creates the branch, `hello-prod` cannot resolve its revision, which is expected
on a new repository.

## 3. One ApplicationSet, values from a second source

`gitops/apps/hello.yaml` generates `hello-dev` and `hello-prod` from one template. The chart and the
per-environment values come from the same repository through Argo CD multi-source (`ref: values`),
so environments differ only by a values file, and adding an environment is one list element.

## 4. The hello project can only create what the chart renders

The `hello` AppProject limits sources to this repository, destinations to `hello-*` namespaces, and
resource kinds to the ones the chart produces. A bad values change cannot create a ClusterRole or
deploy into `kube-system`.

## 5. EKS access entries instead of the aws-auth ConfigMap

The cluster uses `authentication_mode = "API"` and `bootstrap_cluster_creator_admin_permissions = false`.
Admins are listed in Terraform and granted through access entries, so whoever ran `apply` gets no
hidden admin rights, and access is reviewed like any other change.

## 6. Private API endpoint by default

The module keeps the API server private unless the caller opts in. The dev environment opts in so
Terraform and kubectl work without a VPN, but only for `public_access_cidrs`; the module rejects
`0.0.0.0/0` and an empty list. The trivy finding for this is suppressed with that reasoning in
`.trivyignore.yaml`.

## 7. S3 native state locking

The backend uses `use_lockfile = true` (Terraform 1.10+): the lock is an object next to the state in
the same bucket, so there is no DynamoDB table to create, pay for and keep in sync.

## 8. Own modules over community modules

`terraform-aws-modules` would cover the VPC and EKS in a few lines. Here the resources are written out
so that each one is visible, reviewed and covered by a test. For a production platform I would weigh
community modules again: they absorb provider changes, at the price of a large input surface.

## 9. `terraform test` with mocked providers

Module tests run against mocked AWS and Helm providers: they need no credentials, cost nothing and
finish in seconds, so they run on every pull request. They prove the configuration logic (subnet
math, tags, validations, add-on ordering, hardening defaults), not AWS API behaviour. The
configuration has not been applied to a real account yet; that is the next step and the first thing
it would catch is API-side constraints mocks cannot see.

## 10. Environments are namespaces in one cluster

`hello-dev` and `hello-prod` share a cluster to keep the demo cheap. In production I would separate
them into different clusters and AWS accounts, with an ApplicationSet cluster generator instead of
the list generator.

## 11. No ingress controller

The service is reached through `kubectl port-forward` in tests. ingress-nginx has been retired by the
Kubernetes project; on EKS the AWS Load Balancer Controller with the Gateway API would be the next
addition, installed through Pod Identity. For the same reason argocd-server runs with
`server.insecure`: TLS is meant to terminate at that load balancer, and until it exists the UI is
reached through port-forward.

## 12. Removing an environment keeps its workloads

The ApplicationSet sets `preserveResourcesOnDeletion: true`. Dropping an environment from the
generator, or deleting the ApplicationSet by accident (a renamed file pruned by the root app), removes
the Application objects but leaves the Deployments serving traffic; deleting workloads is a separate,
deliberate step. Platform apps such as monitoring keep the resources finalizer and go away with their
Application.

## 13. Child Applications report health

Argo CD stopped assessing the health of Application resources in 1.8, so sync waves between the
children of an app-of-apps do not wait for each other. The Terraform module restores the health check
in `argocd-cm`: monitoring (wave -1) has to be Healthy, CRDs included, before the hello apps (wave 0)
sync their ServiceMonitors.

## 14. One Terraform stack for the cluster and what runs in it

The Helm provider is configured from the EKS module's outputs in the same root module. That keeps
the demo to one `apply`, at a known cost: when the cluster is replaced or destroyed, the provider
loses its endpoint mid-run. Destroy therefore goes in two steps (README). For a long-lived platform
I would split it into a cluster stack and a bootstrap stack that reads the cluster through
`data "aws_eks_cluster"`.
