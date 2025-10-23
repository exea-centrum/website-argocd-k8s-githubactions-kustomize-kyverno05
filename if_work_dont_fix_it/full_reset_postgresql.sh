# Usuń deployment aplikacji
kubectl delete deployment -n davtrografanalokitempo website-argocd-k8s-githubactions-kustomize-kyverno05

# Upewnij się że baza działa
kubectl wait --for=condition=ready pod -n davtrografanalokitempo -l app=postgres --timeout=60s

# Ponownie zastosuj przez ArgoCD
kubectl apply -f argocd/application.yaml

# Poczekaj na synchronizację
sleep 30

# Sprawdź status
kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05