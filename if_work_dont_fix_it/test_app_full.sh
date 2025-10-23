# Sprawdź czy aplikacja działa
APP_POD=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o name | head -1)

# Sprawdź procesy w podzie
echo "Procesy w podzie aplikacji:"
kubectl exec -n davtrografanalokitempo -it $APP_POD -- ps aux

# Sprawdź czy aplikacja nasłuchuje na porcie 8090
echo "Porty nasłuchujące:"
kubectl exec -n davtrografanalokitempo -it $APP_POD -- netstat -tln | grep 8090 || echo "Port 8090 nie nasłuchuje"

# Uruchom port-forward bezpośrednio do poda
pkill -f "kubectl port-forward" || true
kubectl port-forward -n davtrografanalokitempo $APP_POD 8081:8090 &

# Przetestuj aplikację
sleep 5
echo "Test health check:"
curl -s http://localhost:8081/health || echo "Health check failed"

echo ""
echo "Test strony głównej:"
curl -s http://localhost:8081 | head -10 || echo "Strona główna nie działa"