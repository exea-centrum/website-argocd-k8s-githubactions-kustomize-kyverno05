# 1. Sprawdź obraz w Deployment
kubectl get deployment -n davtrografanalokitempo website-argocd-k8s-githubactions-kustomize-kyverno05 -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

# 2. Jeśli to nie jest obraz aplikacji Go, ustaw poprawny
kubectl set image deployment/website-argocd-k8s-githubactions-kustomize-kyverno05 -n davtrografanalokitempo website=ghcr.io/exea-centrum/website-argocd-k8s-githubactions-kustomize-kyverno05:latest

# 3. Poczekaj na restart podów
kubectl rollout status deployment/website-argocd-k8s-githubactions-kustomize-kyverno05 -n davtrografanalokitempo --timeout=120s

# 4. Sprawdź nowe pody
kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05

# 5. Sprawdź procesy w nowym podzie
APP_POD=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o name | head -1)
kubectl exec -n davtrografanalokitempo -it $APP_POD -- ps aux

# 6. Sprawdź logi nowych podów
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --tail=5

# 7. Uruchom port-forward i przetestuj
pkill -f "kubectl port-forward" || true
kubectl port-forward svc/website-argocd-k8s-githubactions-kustomize-kyverno05-service -n davtrografanalokitempo 8081:80 &
sleep 5
curl -s http://localhost:8081/health