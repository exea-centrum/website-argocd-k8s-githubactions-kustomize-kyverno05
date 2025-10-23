#!/bin/bash

set -e

# Konfiguracja
REPO_OWNER="exea-centrum"
REPO_NAME="website-argocd-k8s-githubactions-kustomize-kyverno05"
NAMESPACE="davtrografanalokitempo"
IMAGE_NAME="website-argocd-k8s-githubactions-kustomize-kyverno05"
GITHUB_USER="exea-centrum"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funkcje pomocnicze
print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 nie jest zainstalowany!"
        exit 1
    fi
}

# Sprawdź wymagane narzędzia
print_step "Sprawdzanie wymaganych narzędzi..."
check_command git
check_command kubectl

print_step "🚀 Rozpoczynam tworzenie projektu $REPO_NAME..."

# Tworzenie struktury katalogów
print_step "Tworzenie struktury projektu..."
if [ -d "$REPO_NAME" ]; then
    print_warning "Katalog $REPO_NAME już istnieje, usuwam..."
    rm -rf "$REPO_NAME"
fi

mkdir -p $REPO_NAME
cd $REPO_NAME

# Inicjalizacja git
git init

mkdir -p src templates static/css static/js manifests/base manifests/production/monitoring .github/workflows argocd policies

# 1. Tworzenie plików Go
print_step "Tworzenie aplikacji Go..."

cat > src/main.go << 'EOF'
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total number of HTTP requests",
	}, []string{"path", "method", "status"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "Duration of HTTP requests",
		Buckets: prometheus.DefBuckets,
	}, []string{"path", "method"})

	dbConnectionStatus = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "db_connection_status",
		Help: "Database connection status (1 = connected, 0 = disconnected)",
	})
)

type Config struct {
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	Port       string
}

type PageData struct {
	Title    string
	Content  string
	LastSync time.Time
}

type ScrapedData struct {
	ID      int       `json:"id"`
	Title   string    `json:"title"`
	Content string    `json:"content"`
	Created time.Time `json:"created"`
}

var (
	db        *sql.DB
	templates *template.Template
	config    Config
)

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func initDB() error {
	var err error
	
	config = Config{
		DBHost:     getEnv("DB_HOST", "postgres-service"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "davtro"),
		DBPassword: getEnv("DB_PASSWORD", "password123"),
		DBName:     getEnv("DB_NAME", "davtro_db"),
		Port:       getEnv("PORT", "8090"),
	}
	
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		config.DBHost, config.DBPort, config.DBUser, config.DBPassword, config.DBName)
	
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		return fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(25)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	createTable := `
	CREATE TABLE IF NOT EXISTS scraped_data (
		id SERIAL PRIMARY KEY,
		title TEXT NOT NULL,
		content TEXT NOT NULL,
		created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`
	
	_, err = db.Exec(createTable)
	if err != nil {
		return fmt.Errorf("failed to create table: %w", err)
	}

	dbConnectionStatus.Set(1)
	log.Println("Database initialized successfully")
	return nil
}

func initTemplates() error {
	var err error
	templates, err = template.ParseGlob("templates/*.html")
	if err != nil {
		return fmt.Errorf("failed to parse templates: %w", err)
	}
	return nil
}

func main() {
	if err := initDB(); err != nil {
		log.Fatalf("Database initialization failed: %v", err)
	}
	defer db.Close()

	if err := initTemplates(); err != nil {
		log.Fatalf("Template initialization failed: %v", err)
	}

	http.Handle("/metrics", promhttp.Handler())
	http.HandleFunc("/", instrumentHandler("/", homeHandler))
	http.HandleFunc("/health", instrumentHandler("/health", healthHandler))
	http.HandleFunc("/api/data", instrumentHandler("/api/data", apiHandler))
	http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("static"))))

	port := config.Port
	log.Printf("Server starting on port %s", port)
	
	server := &http.Server{
		Addr:         ":" + port,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
	
	log.Fatal(server.ListenAndServe())
}

func instrumentHandler(path string, handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ww := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		
		defer func() {
			if r := recover(); r != nil {
				log.Printf("Recovered from panic in %s: %v", path, r)
				http.Error(ww, "Internal Server Error", http.StatusInternalServerError)
			}
		}()

		handler(ww, r)
		
		duration := time.Since(start).Seconds()
		httpRequestDuration.WithLabelValues(path, r.Method).Observe(duration)
		httpRequestsTotal.WithLabelValues(path, r.Method, fmt.Sprintf("%d", ww.statusCode)).Inc()
	}
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	data, err := getScrapedData(10)
	if err != nil {
		log.Printf("Error getting scraped data: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	if err := templates.ExecuteTemplate(w, "index.html", map[string]interface{}{
		"Data":  data,
		"Title": "Davtro Website",
	}); err != nil {
		log.Printf("Error executing template: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}
}

func apiHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	data, err := getScrapedData(0)
	if err != nil {
		log.Printf("Error getting scraped data for API: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(data); err != nil {
		log.Printf("Error encoding JSON response: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	status := "healthy"
	code := http.StatusOK

	if err := db.Ping(); err != nil {
		log.Printf("Health check failed: %v", err)
		dbConnectionStatus.Set(0)
		status = "unhealthy"
		code = http.StatusServiceUnavailable
	} else {
		dbConnectionStatus.Set(1)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"status": status})
}

func getScrapedData(limit int) ([]ScrapedData, error) {
	query := "SELECT id, title, content, created FROM scraped_data ORDER BY created DESC"
	if limit > 0 {
		query += fmt.Sprintf(" LIMIT %d", limit)
	}

	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("database query failed: %w", err)
	}
	defer rows.Close()

	var data []ScrapedData
	for rows.Next() {
		var item ScrapedData
		if err := rows.Scan(&item.ID, &item.Title, &item.Content, &item.Created); err != nil {
			return nil, fmt.Errorf("row scan failed: %w", err)
		}
		data = append(data, item)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration failed: %w", err)
	}

	return data, nil
}
EOF

cat > src/go.mod << 'EOF'
module davtro-website

go 1.21

require (
	github.com/lib/pq v1.10.9
	github.com/prometheus/client_golang v1.17.0
)
EOF

# 2. Dockerfile
print_step "Tworzenie Dockerfile..."

cat > Dockerfile << 'EOF'
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY src/go.mod src/go.sum ./
RUN go mod download

COPY src/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates

WORKDIR /root/
COPY --from=builder /app/main .
COPY templates/ ./templates/

# Create static directories and copy files
RUN mkdir -p ./static/css ./static/js
COPY static/ ./static/

EXPOSE 8090
CMD ["./main"]
EOF

# 3. HTML Templates
print_step "Tworzenie szablonów HTML..."

cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{.Title}}</title>
    <link rel="stylesheet" href="/static/css/style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Davtro Website <span class="status-badge">Live</span></h1>
            <p>Monitoring enabled with Prometheus, Grafana, Loki, and Tempo | Powered by ArgoCD + K8s + GitHub Actions</p>
        </div>

        <h2>📊 Scraped Data</h2>
        <div class="data-grid">
        {{range .Data}}
            <div class="data-item">
                <h3>{{.Title}}</h3>
                <p>{{.Content}}</p>
                <div class="timestamp">🕒 Created: {{.Created.Format "2006-01-02 15:04:05"}}</div>
            </div>
        {{else}}
            <div class="data-item" style="grid-column: 1 / -1; text-align: center;">
                <h3>No data available</h3>
                <p>Data will appear here once scraped from the source website.</p>
            </div>
        {{end}}
        </div>

        <div class="nav-links">
            <a href="/api/data">📡 JSON API</a> 
            <a href="/metrics">📈 Metrics</a> 
            <a href="/health">❤️ Health Check</a>
        </div>
    </div>
</body>
</html>
EOF

# 4. Static files
print_step "Tworzenie plików statycznych..."

cat > static/css/style.css << 'EOF'
body { 
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
    margin: 0; 
    padding: 0; 
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
}
.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}
.header { 
    background: rgba(255, 255, 255, 0.95); 
    padding: 30px; 
    border-radius: 15px; 
    margin-bottom: 30px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.1);
    backdrop-filter: blur(10px);
}
.data-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}
.data-item { 
    background: rgba(255, 255, 255, 0.95); 
    border: none; 
    margin: 0; 
    padding: 25px; 
    border-radius: 12px; 
    box-shadow: 0 4px 15px rgba(0,0,0,0.1);
    transition: transform 0.3s ease, box-shadow 0.3s ease;
}
.data-item:hover {
    transform: translateY(-5px);
    box-shadow: 0 8px 25px rgba(0,0,0,0.15);
}
.timestamp { 
    color: #666; 
    font-size: 0.85em; 
    margin-top: 15px;
    padding-top: 15px;
    border-top: 1px solid #eee;
}
h1 { 
    color: #333; 
    margin: 0 0 10px 0;
    font-size: 2.5em;
}
h2 {
    color: white;
    text-align: center;
    margin: 40px 0 30px 0;
    font-size: 2em;
    text-shadow: 0 2px 4px rgba(0,0,0,0.3);
}
h3 {
    color: #333;
    margin: 0 0 15px 0;
    font-size: 1.4em;
}
.nav-links {
    text-align: center;
    margin-top: 30px;
}
.nav-links a {
    color: white;
    text-decoration: none;
    margin: 0 15px;
    padding: 12px 25px;
    border: 2px solid white;
    border-radius: 25px;
    transition: all 0.3s ease;
    display: inline-block;
}
.nav-links a:hover {
    background: white;
    color: #667eea;
}
.status-badge {
    background: #4CAF50;
    color: white;
    padding: 5px 15px;
    border-radius: 20px;
    font-size: 0.8em;
    display: inline-block;
    margin-left: 10px;
}
EOF

cat > static/js/app.js << 'EOF'
// Dodatkowe funkcje JavaScript mogą być dodane tutaj
console.log('Davtro Website loaded successfully');
EOF

# 5. GitHub Actions
print_step "Konfiguracja GitHub Actions..."

cat > .github/workflows/ci-cd.yaml << 'EOF'
name: CI - build & update kustomize

on:
  push:
    branches: [ "main", "master" ]
    paths-ignore:
      - "manifests/production/**"
  workflow_dispatch:

env:
  IMAGE_NAME: website-argocd-k8s-githubactions-kustomize-kyverno05
  KUSTOMIZE_PATH: manifests/production

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write

    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Ensure static directory exists
        run: |
          mkdir -p static/css static/js
          if [ ! -f "static/css/style.css" ]; then
            echo "Creating default CSS..."
            echo "body { margin: 0; padding: 20px; font-family: sans-serif; }" > static/css/style.css
          fi
          if [ ! -f "static/js/app.js" ]; then
            echo "// Default app.js" > static/js/app.js
          fi

      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: "1.21"

      - name: Prepare Go modules
        run: |
          cd src
          go mod tidy
          go mod download

      - name: Build Go application
        run: |
          cd src
          go build -v ./...

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
            ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Install Kustomize
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          sudo mv kustomize /usr/local/bin/

      - name: Update Kustomize image tag
        run: |
          cd ${{ env.KUSTOMIZE_PATH }}
          kustomize edit set image ${{ env.IMAGE_NAME }}=ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

      - name: Commit and push changes
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add ${{ env.KUSTOMIZE_PATH }}/kustomization.yaml
          git diff --staged --quiet || git commit -m "ci: update image tag to ${{ github.sha }}"
          git push
EOF

# 6. Kustomize Manifests
print_step "Tworzenie manifestów Kustomize..."

# ServiceAccount
cat > manifests/base/service-account.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $IMAGE_NAME-sa
  namespace: $NAMESPACE
  labels:
    app: $IMAGE_NAME
    version: v1
EOF

# Deployment
cat > manifests/base/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $IMAGE_NAME
  namespace: $NAMESPACE
  labels:
    app: $IMAGE_NAME
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $IMAGE_NAME
  template:
    metadata:
      labels:
        app: $IMAGE_NAME
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8090"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: $IMAGE_NAME-sa
      initContainers:
      - name: wait-for-db
        image: busybox:1.35
        command: ['sh', '-c', 'until nc -z postgres-service 5432; do echo waiting for database; sleep 2; done; echo Database is ready!']
      containers:
      - name: website
        image: ghcr.io/$REPO_OWNER/$IMAGE_NAME:latest
        ports:
        - containerPort: 8090
        env:
        - name: PORT
          value: "8090"
        - name: DB_HOST
          value: "postgres-service"
        - name: DB_PORT
          value: "5432"
        - name: DB_USER
          value: "davtro"
        - name: DB_PASSWORD
          value: "password123"
        - name: DB_NAME
          value: "davtro_db"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

# Service
cat > manifests/base/service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: $IMAGE_NAME-service
  namespace: $NAMESPACE
  labels:
    app: $IMAGE_NAME
    version: v1
spec:
  selector:
    app: $IMAGE_NAME
  ports:
  - name: http
    port: 80
    targetPort: 8090
    protocol: TCP
  type: ClusterIP
EOF

# Ingress
cat > manifests/base/ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $IMAGE_NAME-ingress
  namespace: $NAMESPACE
  labels:
    app: $IMAGE_NAME
    version: v1
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: $IMAGE_NAME.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $IMAGE_NAME-service
            port:
              number: 80
EOF

# PostgreSQL
cat > manifests/base/postgres.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: $NAMESPACE
  labels:
    app: postgres
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
        version: v1
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: "davtro_db"
        - name: POSTGRES_USER
          value: "davtro"
        - name: POSTGRES_PASSWORD
          value: "password123"
        volumeMounts:
        - mountPath: /var/lib/postgresql/data
          name: postgres-data
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
      volumes:
      - name: postgres-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: $NAMESPACE
  labels:
    app: postgres
    version: v1
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
  type: ClusterIP
EOF

# Secrets
cat > manifests/base/secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: $NAMESPACE
  labels:
    app: $IMAGE_NAME
    version: v1
type: Opaque
data:
  host: cG9zdGdyZXMtc2VydmljZQ==  # postgres-service
  database: ZGF2dHJvX2Ri         # davtro_db
  username: ZGF2dHJv             # davtro
  password: cGFzc3dvcmQxMjM=     # password123
EOF

# ServiceMonitor
cat > manifests/base/service-monitor.yaml << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: $IMAGE_NAME-monitor
  namespace: $NAMESPACE
  labels:
    app: $IMAGE_NAME
    version: v1
spec:
  selector:
    matchLabels:
      app: $IMAGE_NAME
  endpoints:
  - port: "http"
    path: /metrics
    interval: 30s
EOF

# Kustomization Base
cat > manifests/base/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - service-account.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - postgres.yaml
  - secrets.yaml
  - service-monitor.yaml

commonLabels:
  app: $IMAGE_NAME
  version: v1
EOF

# Monitoring Stack
print_step "Tworzenie stacku monitoringu..."

# Tempo ConfigMap
cat > manifests/production/monitoring/tempo-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: davtrografanalokitempo
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
      log_level: info

    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
            http:

    ingester:
      max_block_duration: 5m
      trace_idle_period: 10s

    compactor:
      compaction:
        block_retention: 1h
        compacted_block_retention: 10m

    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/blocks
        wal:
          path: /tmp/tempo/wal
EOF

# Prometheus
cat > manifests/production/monitoring/prometheus.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: $NAMESPACE
  labels:
    app: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config-volume
          mountPath: /etc/prometheus/
        resources:
          requests:
            memory: "512Mi"
            cpu: "300m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: config-volume
        configMap:
          name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: $NAMESPACE
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
  type: ClusterIP
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: $NAMESPACE
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    scrape_configs:
    - job_name: 'website-app'
      static_configs:
      - targets: ['website-argocd-k8s-githubactions-kustomize-kyverno05-service.davtrografanalokitempo.svc.cluster.local:80']
      metrics_path: /metrics
      scrape_interval: 30s
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']
EOF

# Grafana
cat > manifests/production/monitoring/grafana.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: $NAMESPACE
  labels:
    app: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  namespace: $NAMESPACE
spec:
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
  type: ClusterIP
EOF

# Loki
cat > manifests/production/monitoring/loki.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: $NAMESPACE
  labels:
    app: loki
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:latest
        ports:
        - containerPort: 3100
        args:
        - -config.file=/etc/loki/local-config.yaml
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: loki-service
  namespace: $NAMESPACE
spec:
  selector:
    app: loki
  ports:
  - port: 3100
    targetPort: 3100
  type: ClusterIP
EOF

# Tempo
cat > manifests/production/monitoring/tempo.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: $NAMESPACE
  labels:
    app: tempo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:latest
        ports:
        - containerPort: 3200
        args:
        - -config.file=/etc/tempo/tempo.yaml
        volumeMounts:
        - name: config-volume
          mountPath: /etc/tempo
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config-volume
        configMap:
          name: tempo-config
---
apiVersion: v1
kind: Service
metadata:
  name: tempo-service
  namespace: $NAMESPACE
spec:
  selector:
    app: tempo
  ports:
  - port: 3200
    targetPort: 3200
  type: ClusterIP
EOF

# Kustomization Production
cat > manifests/production/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - ../base
  - monitoring/prometheus.yaml
  - monitoring/grafana.yaml
  - monitoring/loki.yaml
  - monitoring/tempo-config.yaml
  - monitoring/tempo.yaml

images:
  - name: ghcr.io/$REPO_OWNER/$IMAGE_NAME
    newName: ghcr.io/$REPO_OWNER/$IMAGE_NAME
    newTag: latest
EOF

# 7. ArgoCD Application
print_step "Tworzenie aplikacji ArgoCD..."

cat > argocd/application.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $IMAGE_NAME-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/$REPO_OWNER/$REPO_NAME.git
    targetRevision: HEAD
    path: manifests/production
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
EOF

# 8. Skrypt konfiguracyjny GHCR
print_step "Tworzenie skryptu konfiguracyjnego GHCR..."

cat > setup-ghcr-secret.sh << 'EOF'
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
EOF

chmod +x setup-ghcr-secret.sh

# 9. Skrypt automatycznego deploymentu - POPRAWIONY
print_step "Tworzenie skryptu automatycznego deploymentu..."

cat > deploy-with-argocd.sh << 'EOF'
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
EOF

chmod +x deploy-with-argocd.sh

# 10. Kyverno Policies
print_step "Tworzenie polityk Kyverno..."

cat > policies/kyverno-policy.yaml << EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  rules:
  - name: check-for-labels
    match:
      any:
      - resources:
          kinds:
          - Deployment
          - Service
          - Ingress
    validate:
      message: "The labels 'app' and 'version' are required."
      pattern:
        metadata:
          labels:
            app: "?*"
            version: "?*"

---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-default-namespace
spec:
  validationFailureAction: enforce
  rules:
  - name: block-default-namespace
    match:
      any:
      - resources:
          kinds:
          - Pod
          - Deployment
          - Service
          namespaces:
          - default
    validate:
      message: "Resources cannot be deployed in the default namespace."
      deny: {}

---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: enforce
  rules:
  - name: check-resource-limits
    match:
      any:
      - resources:
          kinds:
          - Deployment
    validate:
      message: "CPU and memory limits are required."
      pattern:
        spec:
          template:
            spec:
              containers:
              - resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
EOF

# 11. README
print_step "Tworzenie dokumentacji..."

cat > README.md << EOF
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

\`\`\`
$REPO_NAME/
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
\`\`\`

## 🚀 Szybki Deployment

### 1. Utwórz repozytorium GitHub
\`\`\`bash
# Utwórz puste repozytorium: https://github.com/new
# Nazwa: website-argocd-k8s-githubactions-kustomize-kyverno05
\`\`\`

### 2. Inicjalizacja projektu
\`\`\`bash
git add .
git commit -m "Initial commit: Full DevOps pipeline with monitoring"
git remote add origin https://github.com/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno05.git
git push -u origin main
\`\`\`

### 3. Automatyczny deployment
\`\`\`bash
# Skonfiguruj secret GHCR
./setup-ghcr-secret.sh <github-username> <token>

# Automatyczny deployment
./deploy-with-argocd.sh
\`\`\`

## 🔧 Konfiguracja

### Zmienne środowiskowe
- \`DB_HOST\`: Host PostgreSQL
- \`DB_PORT\`: Port PostgreSQL  
- \`DB_USER\`: Użytkownik bazy
- \`DB_PASSWORD\`: Hasło bazy
- \`DB_NAME\`: Nazwa bazy
- \`PORT\`: Port aplikacji (8090)

### Endpointy
- \`/\`: Strona główna
- \`/health\`: Health check
- \`/metrics\`: Metryki Prometheus
- \`/api/data\`: API JSON

## 📊 Monitoring

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin)
- **Loki**: http://localhost:3100
- **Tempo**: http://localhost:3200

## 🔒 Bezpieczeństwo

Polityki Kyverno:
- Wymagane etykiety na zasobach
- Blokada namespace \`default\`
- Wymagane limity zasobów

## 🛠️ Rozwiązywanie problemów

\`\`\`bash
# Sprawdź status podów
kubectl get pods -n davtrografanalokitempo

# Sprawdź logi aplikacji
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05

# Sprawdź status ArgoCD
kubectl get applications -n argocd

# Czyszczenie
kubectl delete -f argocd/application.yaml
kubectl delete namespace davtrografanalokitempo
\`\`\`
EOF

# 12. Inne pliki konfiguracyjne
print_step "Tworzenie dodatkowych plików konfiguracyjnych..."

cat > .gitignore << 'EOF'
# Binaries
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test binary, built with `go test -c`
*.test

# Output of the go coverage tool, specifically when used with LiteIDE
*.out

# Dependency directories (remove the comment below to include it)
# vendor/

# Go workspace file
go.work

# IDE
.vscode/
.idea/

# Kubernetes
kubeconfig.yaml

# Logs
*.log

# Build artifacts
/bin/
/main

# Environment files
.env
.env.local
EOF

cat > .dockerignore << 'EOF'
.git
.github
Dockerfile
README.md
manifests/
argocd/
policies/
.gitignore
EOF

# Finalizacja
print_step "Finalizacja projektu..."

# Commit initial
git add .
git commit -m "Initial commit: Davtro Website with full DevOps stack - Version 05"

print_success "🎉 Projekt $REPO_NAME został utworzony pomyślnie!"
echo ""
echo "📋 Następne kroki:"
echo "1. cd $REPO_NAME"
echo "2. Utwórz repozytorium na GitHubie: https://github.com/new"
echo "3. git remote add origin https://github.com/$REPO_OWNER/$REPO_NAME.git"
echo "4. git push -u origin main"
echo "5. ./setup-ghcr-secret.sh <username> <token>"
echo "6. ./deploy-with-argocd.sh"
echo ""
echo "🚀 Aplikacja będzie automatycznie deployowana przez ArgoCD!"
echo ""
echo "📊 Po deploymencie będziesz mieć dostęp do:"
echo "   - Aplikacja: http://localhost:8081"
echo "   - Grafana: http://localhost:3000 (admin/admin)"
echo "   - Prometheus: http://localhost:9090"
echo "   - Loki: http://localhost:3100"
echo "   - Tempo: http://localhost:3200"