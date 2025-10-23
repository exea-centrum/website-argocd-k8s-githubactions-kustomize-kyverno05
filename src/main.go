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
		Port:       getEnv("PORT", "8090"),  // ZMIENIONE NA 8090
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