# Exercices - Module 03

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 **Connexion lente :** tous les exercices utilisent `nginx:1.27` et `busybox:1.36`, déjà téléchargées. Seul l'exercice 8 (Ingress) demande un téléchargement important : fais-le quand ta connexion est bonne, ou saute-le.
>
> Les commandes sont pour **PowerShell**. Utilise des guillemets **simples** autour des commandes `sh -c '...'`, sinon PowerShell remplace les `$variables`.

---

## Exercice 1 : Ton premier Service

1. Déploie `manifests/deployment.yaml` (3 réplicas).
2. Crée le Service avec `manifests/service-clusterip.yaml`.
3. Affiche le Service et note sa `CLUSTER-IP`.
4. Teste-le depuis un Pod temporaire :
   ```powershell
   kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web
   ```

**Questions**
- Peux-tu atteindre le Service depuis ton navigateur Windows sur la `CLUSTER-IP` ? Pourquoi ?
- Que signifie la colonne `PORT(S)` ?

---

## Exercice 2 : Endpoints et IP des Pods

1. Affiche les Endpoints du Service :
   ```powershell
   kubectl describe svc web
   kubectl get endpointslices -l kubernetes.io/service-name=web
   kubectl get pods -o wide
   ```
2. Compare les IP des Endpoints avec celles des Pods.
3. Scale le Deployment à 5 réplicas, puis à 1. Observe les Endpoints à chaque fois.

**Questions**
- Combien d'IP y a-t-il dans les Endpoints après chaque changement ?
- Qui met à jour cette liste automatiquement ?

---

## Exercice 3 : L'IP du Service est stable, pas celle des Pods

1. Note la `CLUSTER-IP` du Service `web` et l'IP d'un Pod.
2. Supprime tous les Pods : `kubectl delete pods -l app=web`.
3. Attends qu'ils soient recréés, puis compare à nouveau.

**Questions**
- Quelle IP a changé ? Laquelle est restée identique ?
- Pourquoi est-ce exactement le problème que les Services résolvent ?

---

## Exercice 4 : Répartition de charge

1. Fais afficher à chaque Pod son propre nom :
   ```powershell
   kubectl get pods -l app=web -o name | ForEach-Object { kubectl exec $_ -- sh -c 'hostname > /usr/share/nginx/html/index.html' }
   ```
2. Envoie 10 requêtes :
   ```powershell
   kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do wget -qO- http://web; done'
   ```
3. Compte combien de fois chaque Pod répond.

**Questions**
- La répartition est-elle parfaitement égale ? Pourquoi (ou pourquoi pas) ?
- Que se passe-t-il si tu supprimes un Pod pendant le test ?

---

## Exercice 5 : Casser le selector 🔧

1. Copie `service-clusterip.yaml` en `service-casse.yaml`, renomme-le `web-casse`, et change le selector en `app: webb` (deux `b`).
2. Applique-le puis regarde `kubectl describe svc web-casse`.
3. Teste-le avec un Pod temporaire (ajoute `--timeout`, par exemple `wget -T 3 -qO- http://web-casse`).
4. Trouve la cause et corrige-la.

**Questions**
- Que contient la ligne `Endpoints` ?
- Quelle commande te montre les labels réels des Pods pour comparer ?
- Quelle est ta méthode en trois étapes pour diagnostiquer un Service qui ne répond pas ?

---

## Exercice 6 : Le DNS du cluster

1. Résous le Service de trois façons :
   ```powershell
   kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web
   kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.default
   kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.default.svc.cluster.local
   ```
2. Crée un autre namespace et teste depuis celui-ci :
   ```powershell
   kubectl create namespace test
   kubectl run tmp -n test --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web
   kubectl run tmp -n test --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web.default
   ```

**Questions**
- Quel appel échoue, et pourquoi ?
- Comment ton application Spring Boot déclarerait-elle l'adresse du service `postgres` du namespace `data` ?

Nettoyage : `kubectl delete namespace test`.

---

## Exercice 7 : NodePort

1. Applique `manifests/service-nodeport.yaml`.
2. Récupère l'URL avec `minikube service web-nodeport --url` et laisse le terminal ouvert.
3. Ouvre l'URL dans ton navigateur et rafraîchis plusieurs fois.
4. Fais `kubectl get svc` et note les deux ports affichés dans `PORT(S)`.

**Questions**
- Que représentent `80` et `30080` ?
- Pourquoi un NodePort est-il une mauvaise solution pour la production ?

**Bonus (LoadBalancer)** : change `type: NodePort` en `type: LoadBalancer`, applique, regarde `EXTERNAL-IP`. Lance `minikube tunnel` dans un autre terminal et observe la différence.

---

## Exercice 8 : Ingress (optionnel, téléchargement lourd)

1. Active l'Ingress Controller : `minikube addons enable ingress`, puis attends que `kubectl get pods -n ingress-nginx` montre le controller en `Running`.
2. Applique `manifests/api.yaml` puis `manifests/ingress.yaml`.
3. Redirige un port : `kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8081:80` (terminal ouvert).
4. Dans un autre terminal :
   ```powershell
   curl.exe -H "Host: web.local" http://localhost:8081
   curl.exe -H "Host: api.local" http://localhost:8081
   curl.exe http://localhost:8081
   ```

**Questions**
- Pourquoi la troisième requête (sans `Host`) renvoie-t-elle une erreur 404 ?
- Que se passerait-il si tu supprimais l'Ingress Controller mais gardais l'Ingress ?
- Quel est l'avantage d'un Ingress par rapport à un LoadBalancer par Service ?

**Bonus** : ajoute une troisième règle pour un hôte `docs.local` qui pointe vers le Service `web`, et teste-la.

---

## Questions d'auto-évaluation

1. Pourquoi ne peut-on pas utiliser l'IP d'un Pod pour communiquer avec lui ?
2. Quelle est la différence entre `port`, `targetPort` et `nodePort` ?
3. Comment un Service sait-il vers quels Pods envoyer le trafic ?
4. Un Pod non prêt (`Ready` à `false`) reçoit-il du trafic via le Service ?
5. Comment un Pod du namespace `app` appelle-t-il un Service `db` du namespace `data` ?
6. Quand utiliserais-tu ClusterIP, NodePort, LoadBalancer ou Ingress ?
7. Pourquoi un objet Ingress seul ne suffit-il pas ?

---

## Nettoyage

```powershell
kubectl delete ingress main-ingress --ignore-not-found
kubectl delete -f manifests/api.yaml --ignore-not-found
kubectl delete svc web web-nodeport web-casse --ignore-not-found
kubectl delete deployment web
kubectl delete namespace test --ignore-not-found
```