#!/bin/bash

echo "🚀 Końcowy test aplikacji..."

echo "1. Status podów:"
kubectl get pods -n davtrografanalokitempo -o wide

echo ""
echo "2. Logi aplikacji (ostatnie 5 linii):"
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --tail=5

echo ""
echo "3. Test health check:"
curl -s http://localhost:8081/health || echo "Health check nie powiódł się"

echo ""
echo "4. Test strony głównej:"
curl -s http://localhost:8081 | grep -o "<title>.*</title>" || echo "Strona główna nie działa"

echo ""
echo "5. Test bazy danych:"
kubectl exec -n davtrografanalokitempo -it $(kubectl get pods -n davtrografanalokitempo -l app=postgres -o name) -- psql -U davtro -d davtro_db -c "SELECT COUNT(*) FROM scraped_data;" || echo "Błąd połączenia z bazą"

echo ""
echo "✅ Test zakończony!"