#!/bin/bash

set -e

echo "🚀 Automatyczny deployment aplikacji przez ArgoCD..."

# Sprawdź czy ArgoCD jest dostępny
if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server &> /dev/null; then
    echo "❌ ArgoCD nie jest zainstalowany lub nie działa!"
    echo "📦 Instalowanie ArgoCD..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    echo "⏳ Oczekiwanie na uruchomienie ArgoCD..."
    sleep 30
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
fi

# Sprawdź czy secret GHCR istnieje
if ! kubectl get secret ghcr-pull-secret -n davtrografanalokitempo &> /dev/null; then
    echo "❌ Secret GHCR nie istnieje!"
    echo "🔐 Uruchom najpierw: ./setup-ghcr-secret.sh <username> <token>"
    exit 1
fi

# Zastosuj aplikację ArgoCD
echo "📋 Stosowanie aplikacji ArgoCD..."
kubectl apply -f argocd/application.yaml

# Poczekaj na synchronizację
echo "⏳ Oczekiwanie na synchronizację ArgoCD..."
sleep 10

# Sprawdź status aplikacji
echo "📊 Status aplikacji ArgoCD:"
if command -v argocd &> /dev/null; then
    argocd app get website-argocd-k8s-githubactions-kustomize-kyverno05-app || echo "⚠️  Aplikacja może potrzebować więcej czasu na pojawienie się"
else
    echo "ℹ️  ArgoCD CLI nie jest zainstalowane, sprawdź status przez UI"
fi

# Sprawdź status podów
echo "🔍 Sprawdzanie statusu podów..."
timeout=180
counter=0
while [ $counter -lt $timeout ]; do
    if kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 2>/dev/null | grep -q Running; then
        echo "✅ Aplikacja uruchomiona!"
        break
    fi
    echo "⏳ Oczekiwanie na uruchomienie aplikacji... ($counter/$timeout)"
    sleep 10
    counter=$((counter + 10))
done

# Port-forward dla testów
echo "🔌 Uruchamianie port-forward do aplikacji..."
kubectl port-forward svc/website-argocd-k8s-githubactions-kustomize-kyverno05-service -n davtrografanalokitempo 8080:80 &
APP_PID=$!

echo "🔌 Uruchamianie port-forward do monitoringu..."
kubectl port-forward svc/grafana-service -n monitoring 3000:3000 &
GRAFANA_PID=$!
kubectl port-forward svc/prometheus-service -n monitoring 9090:9090 &
PROMETHEUS_PID=$!
kubectl port-forward svc/loki-service -n monitoring 3100:3100 &
LOKI_PID=$!
kubectl port-forward svc/tempo-service -n monitoring 3200:3200 &
TEMPO_PID=$!

echo ""
echo "🎉 DEPLOYMENT ZAKOŃCZONY!"
echo ""
echo "🌐 Dostęp do aplikacji:"
echo "   Aplikacja: http://localhost:8080"
echo "   Metryki:   http://localhost:8080/metrics"
echo "   Health:    http://localhost:8080/health"
echo ""
echo "📊 Monitoring:"
echo "   Grafana:    http://localhost:3000 (admin/admin)"
echo "   Prometheus: http://localhost:9090"
echo "   Loki:       http://localhost:3100"
echo "   Tempo:      http://localhost:3200"
echo ""
echo "🛑 Aby zatrzymać port-forward, uruchom: pkill -f 'kubectl port-forward'"
echo ""
echo "📋 Status podów:"
kubectl get pods -n davtrografanalokitempo
echo ""
echo "📋 Status monitoringu:"
kubectl get pods -n monitoring

# Czekaj na sygnał zakończenia
wait $APP_PID
