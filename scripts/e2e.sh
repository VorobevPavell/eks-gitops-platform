#!/usr/bin/env bash
set -euo pipefail

CLUSTER=${CLUSTER:-gitops-e2e}
REVISION=${REVISION:-$(git rev-parse HEAD)}
CANONICAL_REPO_URL=https://github.com/VorobevPavell/eks-gitops-platform.git
REPO_URL=${REPO_URL:-$CANONICAL_REPO_URL}
ARGOCD_VERSION=v3.5.6
PROMETHEUS_OPERATOR_VERSION=v0.94.2
METRICS_SERVER_CHART_VERSION=3.14.0
IMAGE=hello:e2e
TIMEOUT=300

cd "$(dirname "$0")/.."

log() { printf '\n==> %s\n' "$*"; }

wait_for() {
  local description=$1; shift
  for _ in $(seq "$TIMEOUT"); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  echo "timed out after ${TIMEOUT}s waiting for: $description" >&2
  return 1
}

app_field() {
  kubectl -n argocd get application "$1" -o jsonpath="$2"
}

app_is() {
  [[ "$(app_field "$1" '{.status.sync.status}/{.status.health.status}')" == "Synced/Healthy" ]]
}

dump_state() {
  kubectl -n argocd get applications -o wide || true
  kubectl get pods -A || true
  kubectl -n argocd get application -o yaml | grep -A5 -E 'conditions:|operationState:' || true
}
trap 'status=$?; if (( status != 0 )); then dump_state; fi' EXIT

if ! kind get clusters | grep -qx "$CLUSTER"; then
  log "creating kind cluster $CLUSTER"
  kind create cluster --name "$CLUSTER" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

log "building $IMAGE"
docker build --quiet --build-arg VERSION=e2e -t "$IMAGE" app
kind load docker-image "$IMAGE" --name "$CLUSTER"

log "installing cluster prerequisites: ServiceMonitor CRD, metrics-server"
kubectl apply --server-side -f "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml"
helm upgrade --install metrics-server metrics-server \
  --repo https://kubernetes-sigs.github.io/metrics-server/ \
  --version "$METRICS_SERVER_CHART_VERSION" \
  --namespace kube-system \
  --set 'args={--kubelet-insecure-tls}' \
  --wait

log "installing Argo CD $ARGOCD_VERSION"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
for workload in deployment/argocd-repo-server deployment/argocd-applicationset-controller statefulset/argocd-application-controller; do
  kubectl -n argocd rollout status "$workload" --timeout="${TIMEOUT}s"
done

if [[ -n "${GIT_TOKEN:-}" ]]; then
  log "registering repository credentials"
  kubectl -n argocd create secret generic repo-eks-gitops-platform \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=username=x-access-token \
    --from-literal=password="$GIT_TOKEN" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
fi

log "applying the hello ApplicationSet from $REPO_URL pinned to $REVISION"
kubectl patch --local -f gitops/apps/project-hello.yaml --type=json -o yaml \
  -p "[{\"op\": \"replace\", \"path\": \"/spec/sourceRepos/0\", \"value\": \"$REPO_URL\"}]" \
  | kubectl apply -f -
kubectl patch --local -f gitops/apps/hello.yaml --type=json -o yaml -p "$(cat <<EOF
[
  {"op": "replace", "path": "/spec/template/spec/sources/0/repoURL", "value": "$REPO_URL"},
  {"op": "replace", "path": "/spec/template/spec/sources/1/repoURL", "value": "$REPO_URL"},
  {"op": "replace", "path": "/spec/generators/0/list/elements/0/revision", "value": "$REVISION"},
  {"op": "replace", "path": "/spec/generators/0/list/elements/1/revision", "value": "$REVISION"},
  {"op": "add", "path": "/spec/template/spec/sources/0/helm/parameters", "value": [
    {"name": "image.repository", "value": "${IMAGE%%:*}"},
    {"name": "image.tag", "value": "${IMAGE##*:}"},
    {"name": "image.pullPolicy", "value": "Never"}
  ]}
]
EOF
)" | kubectl apply -f -

for env in dev prod; do
  app="hello-$env"
  log "waiting for $app to become Synced/Healthy"
  wait_for "$app to exist" kubectl -n argocd get application "$app"
  wait_for "$app Synced/Healthy" app_is "$app"
  synced=$(app_field "$app" '{.status.sync.revisions[0]}')
  [[ "$synced" == "$REVISION" ]] || { echo "$app synced $synced, expected $REVISION" >&2; exit 1; }
done

log "checking prod-only resources"
kubectl -n hello-prod get hpa/hello pdb/hello servicemonitor/hello

log "smoke-testing hello-dev through its Service"
kubectl -n hello-dev port-forward svc/hello 18080:80 >/dev/null &
forward=$!
trap 'status=$?; kill $forward 2>/dev/null || true; if (( status != 0 )); then dump_state; fi' EXIT
wait_for "port-forward" curl -fsS http://127.0.0.1:18080/healthz
curl -fsS http://127.0.0.1:18080/ | grep -q '"environment":"dev"'
curl -fsS http://127.0.0.1:18080/metrics | grep -q 'hello_http_requests_total'
kill $forward

log "deleting deployment/hello in hello-dev; Argo CD must restore it"
kubectl -n hello-dev delete deployment hello --wait
wait_for "deployment restored" kubectl -n hello-dev get deployment hello
kubectl -n hello-dev rollout status deployment/hello --timeout="${TIMEOUT}s"
wait_for "hello-dev Synced/Healthy after self-heal" app_is hello-dev

log "all checks passed for $REVISION"
