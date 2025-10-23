#!/bin/bash

echo "🔧 Kompleksowa naprawa bazy danych..."

echo "1. Sprawdzanie istniejących baz danych..."
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "\l"

echo ""
echo "2. Tworzenie bazy danych i użytkownika..."
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "CREATE DATABASE davtro_db;" 2>/dev/null || echo "Baza już istnieje"
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "CREATE USER davtro WITH PASSWORD 'password123';" 2>/dev/null || echo "Użytkownik już istnieje"
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE davtro_db TO davtro;"

echo ""
echo "3. Sprawdzanie połączenia z aplikacji..."
APP_POD=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o name | head -1)
kubectl exec -n davtrografanalokitempo -it $APP_POD -- sh -c 'PGPASSWORD=password123 psql -h postgres-service -U davtro -d davtro_db -c "\dt"' || echo "Błąd połączenia"

echo ""
echo "4. Restartowanie aplikacji..."
kubectl rollout restart deployment/website-argocd-k8s-githubactions-kustomize-kyverno05 -n davtrografanalokitempo

echo "⏳ Oczekiwanie na uruchomienie..."
kubectl wait --for=condition=ready pod -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --timeout=120s

echo ""
echo "5. Logi aplikacji:"
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --tail=5

echo ""
echo "✅ Naprawa zakończona!"