# Sprawdź czy aplikacja działa
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --tail=10

# Sprawdź procesy w podzie
APP_POD=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o name | head -1)
kubectl exec -n davtrografanalokitempo -it $APP_POD -- ps aux

# Uruchom port-forward
kubectl port-forward svc/website-argocd-k8s-githubactions-kustomize-kyverno05-service -n davtrografanalokitempo 8081:80 &

# Przetestuj
curl http://localhost:8081/health


