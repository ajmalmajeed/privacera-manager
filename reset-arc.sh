#!/bin/bash

set -e

echo "🔄 Step 1: Cleaning up old installs..."

# Delete ARC
helm uninstall actions-runner-controller -n github-actions-runner --ignore-not-found || true
kubectl delete namespace github-actions-runner --ignore-not-found=true

# Delete cert-manager
kubectl delete namespace cert-manager --ignore-not-found=true

# Delete cert-manager CRDs
kubectl delete crd certificaterequests.cert-manager.io \
  certificates.cert-manager.io \
  challenges.acme.cert-manager.io \
  clusterissuers.cert-manager.io \
  issuers.cert-manager.io \
  orders.acme.cert-manager.io \
  --ignore-not-found=true

# Delete leftover webhooks
kubectl delete validatingwebhookconfiguration cert-manager-webhook || true
kubectl delete mutatingwebhookconfiguration cert-manager-webhook || true

echo "✅ Cleanup complete."

echo "🔄 Step 2: Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml

echo "⏳ Waiting for cert-manager pods..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=180s
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=180s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=180s

echo "✅ Cert-manager installed."

echo "🔄 Step 3: Installing Actions Runner Controller..."
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

helm upgrade --install actions-runner-controller \
  actions-runner-controller/actions-runner-controller \
  --namespace github-actions-runner \
  --create-namespace \
  --values github_actions_values.yml

echo "⏳ Waiting for ARC pods..."
kubectl rollout status deployment/actions-runner-controller -n github-actions-runner --timeout=180s
kubectl rollout status deployment/actions-runner-controller-webhook -n github-actions-runner --timeout=180s

echo "✅ ARC installed."

echo "🔄 Step 4: Creating GitHub PAT secret..."
# Replace with your actual PAT before running
GITHUB_PAT=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

kubectl create secret generic github-token \
  --from-literal=token=$GITHUB_PAT \
  -n github-actions-runner --dry-run=client -o yaml | kubectl apply -f -

echo "✅ GitHub PAT secret created."

echo "🔄 Step 5: Deploying Runner..."
kubectl apply -f github-self-hosted-runner.yaml

echo "⏳ Waiting for Runner pod..."
kubectl get pods -n github-actions-runner -w
