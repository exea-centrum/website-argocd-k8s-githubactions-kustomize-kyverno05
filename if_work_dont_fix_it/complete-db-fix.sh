#!/bin/bash

echo "🔧 Kompletna naprawa bazy danych i aplikacji..."

echo "1. Tworzenie brakujących baz danych..."
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "CREATE DATABASE IF NOT EXISTS davtro;" 2>/dev/null
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "CREATE DATABASE IF NOT EXISTS davtro_db;" 2>/dev/null
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE davtro TO davtro;" 2>/dev/null
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE davtro_db TO davtro;" 2>/dev/null

echo ""
echo "2. Lista baz danych:"
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U postgres -c "\l"

echo ""
echo "3. Aplikacja deployment z poprawionym init container..."
kubectl apply -f fixed-deployment-final.yaml

echo ""
echo "4. Oczekiwanie na uruchomienie aplikacji..."
kubectl rollout status deployment/website-argocd-k8s-githubactions-kustomize-kyverno05 -n davtrografanalokitempo --timeout=180s

echo ""
echo "5. Sprawdzanie logów aplikacji:"
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --tail=5

echo ""
echo "6. Sprawdzanie logów init container:"
kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o name | head -1 | xargs -I {} kubectl logs -n davtrografanalokitempo {} -c wait-for-db

echo ""
echo "✅ Naprawa zakończona!"