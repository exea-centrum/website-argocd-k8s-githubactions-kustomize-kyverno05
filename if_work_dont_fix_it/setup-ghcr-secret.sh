#!/bin/bash

set -e

echo "🔐 Konfiguracja GHCR pull secret..."

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ Użycie: ./setup-ghcr-secret.sh <GITHUB_USERNAME> <GITHUB_TOKEN>"
    echo "   Token musi mieć uprawnienia: read:packages, write:packages"
    exit 1
fi

GITHUB_USERNAME=$1
GITHUB_TOKEN=$2
NAMESPACE="davtrografanalokitempo"
SECRET_NAME="ghcr-pull-secret"

# Sprawdź czy secret już istnieje
if kubectl get secret $SECRET_NAME -n $NAMESPACE &> /dev/null; then
    echo "🔄 Secret już istnieje, aktualizuję..."
    kubectl delete secret $SECRET_NAME -n $NAMESPACE --ignore-not-found=true
fi

# Utwórz nowy secret
kubectl create secret docker-registry $SECRET_NAME \
  --namespace=$NAMESPACE \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USERNAME \
  --docker-password=$GITHUB_TOKEN

# Dodaj imagePullSecrets do service account
kubectl patch serviceaccount website-argocd-k8s-githubactions-kustomize-kyverno05-sa -n $NAMESPACE --type='json' -p='[{"op": "add", "path": "/imagePullSecrets", "value": [{"name": "ghcr-pull-secret"}]}]'

echo "✅ GHCR secret utworzony pomyślnie!"
echo "🔍 Sprawdź secret: kubectl get secret $SECRET_NAME -n $NAMESPACE -o yaml"
