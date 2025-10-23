# 🚀 Davtro Website - ArgoCD + K8s + GitHub Actions + Kustomize + Kyverno

Kompleksowe rozwiązanie DevOps z pełnym pipeline CI/CD, monitoringiem i politykami bezpieczeństwa.

## 📋 Architektura

- **Aplikacja**: Go + PostgreSQL
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
├── .github/workflows/     # GitHub Actions
├── argocd/               # Konfiguracja ArgoCD
├── policies/             # Polityky Kyverno
└── monitoring/           # Stack monitoringu
```

## ⚙️ Szybkie uruchomienie

### 1. Inicjalizacja
```bash
git clone https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno05.git
cd website-argocd-k8s-githubactions-kustomize-kyverno05
```

### 2. Instalacja ArgoCD na MicroK8s
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Konfiguracja GHCR
```bash
./setup-ghcr-secret.sh <github-username> <github-token>
```

### 4. Deploy aplikacji przez ArgoCD
```bash
kubectl apply -f argocd/application.yaml
```

### 5. Dostęp do ArgoCD
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Login: admin, Hasło: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## 🔧 Konfiguracja

### Zmienne środowiskowe
- `DB_HOST`: Host PostgreSQL
- `DB_PORT`: Port PostgreSQL  
- `DB_USER`: Użytkownik bazy
- `DB_PASSWORD`: Hasło bazy
- `DB_NAME`: Nazwa bazy
- `PORT`: Port aplikacji (domyślnie 8080)

### Endpointy
- `/`: Strona główna
- `/health`: Health check
- `/metrics`: Metryki Prometheus
- `/api/data`: API JSON

## 📊 Monitoring

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin)
- **Loki**: http://localhost:3100
- **Tempo**: http://localhost:3200

## 🔒 Bezpieczeństwo

Polityki Kyverno:
- Wymagane etykiety na zasobach
- Blokada namespace `default`
- Wymagane limity zasobów

## 🚀 GitHub Actions

Pipeline automatycznie:
1. Buduje obraz Dockera
2. Push do GHCR  
3. Aktualizuje Kustomize
4. ArgoCD automatycznie deployuje na MicroK8s

## 📝 Logowanie

Logi dostępne przez `kubectl logs`

## 🤝 Contributing

1. Fork the project
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 Licencja

MIT License - szczegóły w pliku LICENSE.
