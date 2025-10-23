#!/bin/bash

set -e

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}▶${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
print_error() { echo -e "${RED}❌${NC} $1"; }

echo "🚀 Automatyczny deployment aplikacji przez ArgoCD..."

# Sprawdź czy ArgoCD jest dostępny
if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server &> /dev/null; then
    print_step "ArgoCD nie jest zainstalowany, instaluję..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    print_step "Oczekiwanie na uruchomienie ArgoCD..."
    sleep 30
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
fi

# Sprawdź czy secret GHCR istnieje
if ! kubectl get secret ghcr-pull-secret -n davtrografanalokitempo &> /dev/null; then
    print_error "Secret GHCR nie istnieje!"
    echo "🔐 Uruchom najpierw: ./setup-ghcr-secret.sh <username> <token>"
    exit 1
fi

# Zastosuj aplikację ArgoCD
print_step "Stosowanie aplikacji ArgoCD..."
kubectl apply -f argocd/application.yaml

# Poczekaj na synchronizację
print_step "Oczekiwanie na synchronizację ArgoCD..."
sleep 30

# Sprawdź status aplikacji
print_step "Status aplikacji ArgoCD:"
if command -v argocd &> /dev/null; then
    argocd app get website-argocd-k8s-githubactions-kustomize-kyverno05-app || echo "⚠️  Aplikacja może potrzebować więcej czasu na pojawienie się"
else
    echo "ℹ️  ArgoCD CLI nie jest zainstalowane, sprawdź status przez UI:"
    echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "Hasło: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d"
fi

# Sprawdź status podów
print_step "Sprawdzanie statusu podów..."
timeout=300
counter=0
all_running=false

while [ $counter -lt $timeout ]; do
    RUNNING_PODS=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 2>/dev/null | grep Running | wc -l)
    TOTAL_PODS=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 2>/dev/null | grep -v NAME | wc -l)
    
    if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -ge 1 ]; then
        all_running=true
        print_success "Aplikacja uruchomiona!"
        break
    fi
    echo "⏳ Oczekiwanie na uruchomienie aplikacji... ($counter/$timeout)"
    sleep 10
    counter=$((counter + 10))
done

if [ "$all_running" = false ]; then
    print_warning "Timeout - sprawdzam status podów..."
    kubectl get pods -n davtrografanalokitempo
fi

# Port-forward dla testów (używamy portu 8081 zamiast 8080)
print_step "Uruchamianie port-forward do aplikacji (port 8081)..."
kubectl port-forward svc/website-argocd-k8s-githubactions-kustomize-kyverno05-service -n davtrografanalokitempo 8081:80 &
APP_PID=$!

print_step "Uruchamianie port-forward do monitoringu..."
kubectl port-forward svc/grafana-service -n davtrografanalokitempo 3000:3000 &
GRAFANA_PID=$!
kubectl port-forward svc/prometheus-service -n davtrografanalokitempo 9090:9090 &
PROMETHEUS_PID=$!
kubectl port-forward svc/loki-service -n davtrografanalokitempo 3100:3100 &
LOKI_PID=$!
kubectl port-forward svc/tempo-service -n davtrografanalokitempo 3200:3200 &
TEMPO_PID=$!

# Funkcja czyszczenia
cleanup() {
    echo ""
    print_step "Zatrzymywanie port-forward..."
    pkill -f "kubectl port-forward"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo ""
print_success "DEPLOYMENT ZAKOŃCZONY!"
echo ""
echo "🌐 Dostęp do aplikacji:"
echo "   Aplikacja: http://localhost:8081"
echo "   Metryki:   http://localhost:8081/metrics"
echo "   Health:    http://localhost:8081/health"
echo ""
echo "📊 Monitoring:"
echo "   Grafana:    http://localhost:3000 (admin/admin)"
echo "   Prometheus: http://localhost:9090"
echo "   Loki:       http://localhost:3100"
echo "   Tempo:      http://localhost:3200"
echo ""
echo "🛑 Aby zatrzymać port-forward, naciśnij Ctrl+C"
echo ""
echo "📋 Status podów:"
kubectl get pods -n davtrografanalokitempo

# Czekaj na sygnał zakończenia
wait $APP_PID
