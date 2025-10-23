# 🚀 Davtro Website - ArgoCD + K8s + GitHub Actions + Kustomize + Kyverno

Kompleksowe rozwiązanie DevOps z pełnym pipeline CI/CD, monitoringiem i politykami bezpieczeństwa.

## 📋 Architektura

- **Aplikacja**: Go + PostgreSQL (port 8090)
- **CI/CD**: GitHub Actions + ArgoCD
- **Infrastruktura**: Kubernetes + Kustomize
- **Bezpieczeństwo**: Kyverno Policies
- **Monitoring**: Prometheus + Grafana + Loki + Tempo
- **GitOps**: ArgoCD bezpośrednio z GitHub

## 🏗️ Struktura projektu

```
website-argocd-k8s-githubactions-kustomize-kyverno05/
├── src/                    # Kod źródłowy Go
├── templates/              # Szablony HTML
├── static/                 # Pliki statyczne
├── manifests/             # Manifesty K8s
│   ├── base/              # Bazowe manifesty
│   └── production/        # Overlay production
│       └── monitoring/    # Stack monitoringu
├── .github/workflows/     # GitHub Actions
├── argocd/               # Konfiguracja ArgoCD
└── policies/             # Polityky Kyverno
```

## 🚀 Szybki Deployment

### 1. Utwórz repozytorium GitHub
```bash
# Utwórz puste repozytorium: https://github.com/new
# Nazwa: website-argocd-k8s-githubactions-kustomize-kyverno05
```

### 2. Inicjalizacja projektu
```bash
git add .
git commit -m "Initial commit: Full DevOps pipeline with monitoring"
git remote add origin https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno05.git
git push -u origin main
```

### 3. Automatyczny deployment
```bash
# Skonfiguruj secret GHCR
./setup-ghcr-secret.sh <github-username> <token>

# Automatyczny deployment
./deploy-with-argocd.sh
```

## 🔧 Konfiguracja

### Zmienne środowiskowe
- `DB_HOST`: Host PostgreSQL
- `DB_PORT`: Port PostgreSQL  
- `DB_USER`: Użytkownik bazy
- `DB_PASSWORD`: Hasło bazy
- `DB_NAME`: Nazwa bazy
- `PORT`: Port aplikacji (8090)

### Endpointy
- `/`: Strona główna
- `/health`: Health check
- `/metrics`: Metryki Prometheus
- `/api/data`: API JSON

## 📊 Monitoring

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001 (admin/admin)
- **Loki**: http://localhost:3100
- **Tempo**: http://localhost:3200

## 🔒 Bezpieczeństwo

Polityki Kyverno:
- Wymagane etykiety na zasobach
- Blokada namespace `default`
- Wymagane limity zasobów

## 🛠️ Rozwiązywanie problemów

```bash
# Sprawdź status podów
kubectl get pods -n davtrografanalokitempo

# Sprawdź logi aplikacji
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05

# Sprawdź status ArgoCD
kubectl get applications -n argocd

# Czyszczenie
kubectl delete -f argocd/application.yaml
kubectl delete namespace davtrografanalokitempo
```
