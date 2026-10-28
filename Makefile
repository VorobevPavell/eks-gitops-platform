TF_MODULES := network eks argocd
KUBECONFORM_CRDS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
KUBECONFORM := kubeconform -strict -summary -schema-location default -schema-location '$(KUBECONFORM_CRDS)'

.PHONY: test test-app test-terraform lint lint-terraform lint-k8s e2e e2e-down

test: test-app test-terraform

test-app:
	cd app && go vet ./... && go test -race ./...

test-terraform:
	@for m in $(TF_MODULES); do \
		echo "--- terraform test: $$m"; \
		(cd terraform/modules/$$m && terraform init -backend=false -input=false >/dev/null && terraform test) || exit 1; \
	done

lint: lint-terraform lint-k8s

lint-terraform:
	terraform fmt -recursive -check terraform
	cd terraform/envs/dev && terraform init -backend=false -input=false >/dev/null && terraform validate
	tflint --init --config $(CURDIR)/terraform/.tflint.hcl
	cd terraform && tflint --recursive --config $(CURDIR)/terraform/.tflint.hcl

lint-k8s:
	@for env in dev prod; do \
		helm lint charts/hello -f gitops/envs/$$env/values.yaml || exit 1; \
		helm template hello charts/hello -f gitops/envs/$$env/values.yaml | $(KUBECONFORM) - || exit 1; \
	done
	$(KUBECONFORM) gitops/bootstrap gitops/apps

e2e:
	GIT_TOKEN=$${GIT_TOKEN:-$$(gh auth token 2>/dev/null)} scripts/e2e.sh

e2e-down:
	kind delete cluster --name gitops-e2e
