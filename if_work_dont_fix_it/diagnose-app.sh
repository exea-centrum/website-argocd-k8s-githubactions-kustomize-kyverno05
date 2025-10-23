#!/bin/bash

echo "🔍 Diagnostyka aplikacji..."

echo "1. Status podów:"
kubectl get pods -n davtrografanalokitempo -o wide

echo ""
echo "2. Logi aplikacji:"
kubectl logs -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 --tail=10

echo ""
echo "3. Status bazy danych:"
kubectl get pods -n davtrografanalokitempo -l app=postgres

echo ""
echo "4. Events:"
kubectl get events -n davtrografanalokitempo --sort-by=.lastTimestamp | tail -10

echo ""
echo "5. Sprawdzanie wewnątrz poda aplikacji:"
APP_POD=$(kubectl get pods -n davtrografanalokitempo -l app=website-argocd-k8s-githubactions-kustomize-kyverno05 -o name 2>/dev/null | head -1)
if [ -n "$APP_POD" ]; then
    echo "   Procesy w podzie:"
    kubectl exec -n davtrografanalokitempo -it $APP_POD -- ps aux 2>/dev/null || echo "   Nie można sprawdzić procesów"
    
    echo "   Porty nasłuchujące:"
    kubectl exec -n davtrografanalokitempo -it $APP_POD -- netstat -tln 2>/dev/null || echo "   Nie można sprawdzić portów"
    
    echo "   Pliki w /root/:"
    kubectl exec -n davtrografanalokitempo -it $APP_POD -- ls -la /root/ 2>/dev/null || echo "   Nie można sprawdzić plików"
else
    echo "   Nie znaleziono poda aplikacji"
fi
