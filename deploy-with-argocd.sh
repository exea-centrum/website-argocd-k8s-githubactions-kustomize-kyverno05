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

# Funkcja do sprawdzania wolnych portów
find_free_port() {
    local base_port=$1
    local port=$base_port
    while netstat -tuln | grep -q ":$port "; do
        port=$((port + 1))
        if [ $port -gt $((base_port + 20)) ]; then
            echo $base_port
            return
        fi
    done
    echo $port
}

echo "🚀 Automatyczny deployment aplikacji przez ArgoCD..."

# Znajdź wolne porty
APP_PORT=$(find_free_port 8081)
GRAFANA_PORT=$(find_free_port 3001)
PROMETHEUS_PORT=9090  # Zwykle wolny
LOKI_PORT=3100        # Zwykle wolny  
TEMPO_PORT=3200       # Zwykle wolny

print_step "Używanie portów: App:$APP_PORT, Grafana:$GRAFANA_PORT, Prometheus:$PROMETHEUS_PORT, Loki:$LOKI_PORT, Tempo:$TEMPO_PORT"

# Zatrzymaj istniejące port-forward
pkill -f "kubectl port-forward" || true
sleep 2

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
all_healthy=false

while [ $counter -lt $timeout ]; do
    # Sprawdź czy PostgreSQL działa
    POSTGRES_READY=$(kubectl get pods -n davtrografanalokitempo -l app=postgres -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    # Sprawdź czy aplikacja działa
    READY_PODS=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o jsonpath='{range .items[*]}{.status.containerStatuses[?(@.ready==true)].ready}{"\n"}{end}' | grep -c true)
    TOTAL_PODS=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --no-headers | wc -l)
    
    if [ "$POSTGRES_READY" = "true" ] && [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -ge 1 ]; then
        # Sprawdź czy aplikacja odpowiada na health check
        POD_NAME=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o name | head -1 | cut -d'/' -f2)
        if kubectl exec -n davtrografanalokitempo $POD_NAME -- wget -q -T 5 -O- http://localhost:8090/health >/dev/null 2>&1; then
            all_healthy=true
            print_success "Aplikacja uruchomiona i odpowiada!"
            break
        fi
    fi
    echo "⏳ Oczekiwanie na uruchomienie... PostgreSQL: $POSTGRES_READY, App: $READY_PODS/$TOTAL_PODS ($counter/$timeout)"
    sleep 10
    counter=$((counter + 10))
done

if [ "$all_healthy" = false ]; then
    print_warning "Timeout - sprawdzam status podów i logi..."
    kubectl get pods -n davtrografanalokitempo
    echo ""
    print_step "Logi aplikacji:"
    kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --tail=20
    echo ""
    print_step "Logi PostgreSQL:"
    kubectl logs -n davtrografanalokitempo -l app=postgres --tail=10
    echo ""
    print_step "Events:"
    kubectl get events -n davtrografanalokitempo --sort-by=.lastTimestamp | tail -10
fi

# Port-forward tylko jeśli aplikacja jest zdrowa
if [ "$all_healthy" = true ]; then
    print_step "Uruchamianie port-forward do aplikacji (port $APP_PORT)..."
    kubectl port-forward svc/website-argocd-k8s-githubactions-kustomize-kyverno05-service -n davtrografanalokitempo $APP_PORT:80 &
    APP_PID=$!
    sleep 2

    print_step "Uruchamianie port-forward do monitoringu..."
    kubectl port-forward svc/grafana-service -n davtrografanalokitempo $GRAFANA_PORT:3000 &
    GRAFANA_PID=$!
    sleep 1
    
    kubectl port-forward svc/prometheus-service -n davtrografanalokitempo $PROMETHEUS_PORT:9090 &
    PROMETHEUS_PID=$!
    sleep 1
    
    kubectl port-forward svc/loki-service -n davtrografanalokitempo $LOKI_PORT:3100 &
    LOKI_PID=$!
    sleep 1
    
    kubectl port-forward svc/tempo-service -n davtrografanalokitempo $TEMPO_PORT:3200 &
    TEMPO_PID=$!
    sleep 1

    # Funkcja czyszczenia
    cleanup() {
        echo ""
        print_step "Zatrzymywanie port-forward..."
        pkill -f "kubectl port-forward" || true
        exit 0
    }

    trap cleanup SIGINT SIGTERM

    echo ""
    print_success "DEPLOYMENT ZAKOŃCZONY!"
    echo ""
    echo "🌐 Dostęp do aplikacji:"
    echo "   Aplikacja: http://localhost:$APP_PORT"
    echo "   Metryki:   http://localhost:$APP_PORT/metrics"
    echo "   Health:    http://localhost:$APP_PORT/health"
    echo ""
    echo "📊 Monitoring:"
    echo "   Grafana:    http://localhost:$GRAFANA_PORT (admin/admin)"
    echo "   Prometheus: http://localhost:$PROMETHEUS_PORT"
    echo "   Loki:       http://localhost:$LOKI_PORT"
    echo "   Tempo:      http://localhost:$TEMPO_PORT"
    echo ""
    echo "🛑 Aby zatrzymać port-forward, naciśnij Ctrl+C"
else
    print_error "Aplikacja nie jest zdrowa, pomijam port-forward"
    echo "🔍 Sprawdź logi powyżej i napraw problemy przed ponownym uruchomieniem"
    exit 1
fi

echo ""
echo "📋 Status podów:"
kubectl get pods -n davtrografanalokitempo

echo ""
print_step "Testowanie aplikacji..."
if curl -s http://localhost:$APP_PORT/health >/dev/null; then
    print_success "Aplikacja działa poprawnie!"
else
    print_warning "Aplikacja nie odpowiada na health check, sprawdź logi"
fi

# Czekaj na sygnał zakończenia
wait $APP_PID
