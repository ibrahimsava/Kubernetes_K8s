# Exercices - Module 10

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 Les exercices 1 à 5 n'utilisent que `busybox:1.36`, déjà chez toi. Les exercices 7 à 10 demandent les images de Prometheus et Grafana (lourdes) : fais-les quand ta connexion est bonne.
>
> Commandes pour **PowerShell**. `Select-String` est l'équivalent de `grep`.
>
> 🔒 N'écris jamais de vrais mots de passe dans tes manifests ou tes tableaux de bord exportés.

---

## Exercice 1 : Maîtriser `kubectl logs`

Avec le Pod `logger` (`manifests/logger.yaml`), écris la commande pour :

1. afficher les 10 dernières lignes du conteneur `api`
2. afficher les logs de la dernière minute
3. ne garder que les lignes `ERROR`
4. **compter** combien de lignes `WARN` ou `ERROR` il y a (indice : `Measure-Object`)
5. afficher les logs des deux conteneurs avec leur nom en préfixe
6. suivre les logs du conteneur `worker` en direct

**Questions**
- Quelle ligne d'erreur revient toutes les 10 requêtes ? Et pour les avertissements ?
- Pourquoi `kubectl logs logger` seul affiche-t-il un message sur le conteneur choisi ?
- Que se passe-t-il pour ces logs si tu supprimes le Pod ?

---

## Exercice 2 : `--previous` et le crash 🔧

1. Applique `manifests/crasher.yaml` et attends `CrashLoopBackOff`.
2. Compare `kubectl logs crasher` et `kubectl logs crasher --previous`.
3. Lis `kubectl describe pod crasher` : exit code, restart count, événements.
4. Note, dans l'ordre, les **quatre commandes** que tu lances face à un Pod qui redémarre en boucle.

**Questions**
- Pourquoi `kubectl logs` (sans `--previous`) peut-il paraître vide ou incomplet ?
- Quelle information trouves-tu dans `describe` que les logs ne contiennent pas ?
- Qui a écrit le message « connexion refusée » : Kubernetes ou l'application ?

---

## Exercice 3 : Logs ou événements ?

Pour chaque situation, indique **où chercher** (logs de l'application ou événements Kubernetes) :

1. Un Pod reste en `ImagePullBackOff`.
2. Une API répond 500 sur une route précise.
3. Un conteneur est tué avec `OOMKilled`.
4. Une probe de readiness échoue.
5. Une exception `NullPointerException` apparaît.
6. Un Pod reste `Pending`.

**Question :** pourquoi est-il utile de consulter les deux sources lors d'une enquête ?

---

## Exercice 4 : Débogage avec un conteneur éphémère

1. Lance `kubectl debug -it logger --image=busybox:1.36 --target=api -- sh`.
2. Dans le shell, lance `ps` et repère le processus du conteneur `api`.
3. Quitte, puis lance `kubectl get pod logger -o jsonpath='{.spec.ephemeralContainers[*].name}'`.

**Questions**
- Dans quel cas ce mécanisme est-il indispensable (image sans shell, par exemple) ?
- Peux-tu supprimer un conteneur éphémère d'un Pod ?
- Quel est le risque de laisser ce droit à tout le monde ? (Pense à RBAC, module 07.)

---

## Exercice 5 : Concevoir un log structuré

1. Écris **à la main** une ligne de log JSON pour l'événement : « le paiement de la commande 4521 a été refusé pour le client 87 ».
2. Liste les **champs** que tu y mets (par exemple `timestamp`, `level`, `service`, `traceId`, `message`).
3. Indique les champs que tu ne dois **jamais** y mettre.

**Questions**
- Qu'apporte un log JSON par rapport à une phrase libre quand tu le cherches dans Loki ou Elasticsearch ?
- À quoi sert le `traceId` quand une requête traverse trois services ?
- Pourquoi ne faut-il pas loguer un numéro de carte bancaire ou un jeton ?

---

## Exercice 6 : Types de métriques

Classe chaque métrique en **counter**, **gauge** ou **histogram**, et justifie :

| Métrique | Type |
|----------|------|
| Nombre total de requêtes HTTP reçues | ? |
| Mémoire utilisée par la JVM | ? |
| Durée des requêtes HTTP | ? |
| Nombre de connexions actives à la base | ? |
| Nombre total d'erreurs depuis le démarrage | ? |
| Taille de la file de messages | ? |
| Température d'un serveur | ? |

**Questions**
- Pourquoi n'affiche-t-on presque jamais un counter brut sur un graphique ?
- Que fait `rate(x[1m])` à un counter ?
- Pourquoi un label `user_id` dans une métrique est-il dangereux ? Qu'est-ce que la cardinalité ?

---

## Exercice 7 : Lire des métriques brutes

1. Applique `manifests/web-metrics.yaml` et attends `2/2 Running`.
2. Ouvre l'accès : `kubectl port-forward svc/web-metrics 8080:80 9113:9113`.
3. Lis `curl.exe -s http://localhost:9113/metrics | Select-String "^nginx_"`.
4. Note la valeur de `nginx_http_requests_total`, envoie 30 requêtes, relis-la.

**Questions**
- Quelle est la valeur de `nginx_up` ? Que signifie-t-elle ?
- Le compteur a-t-il augmenté d'exactement 30 ? Pourquoi (indice : l'exporter interroge lui aussi Nginx) ?
- Comment s'appelle le conteneur qui produit ce texte ? Pourquoi le met-on dans le même Pod que Nginx ?

---

## Exercice 8 : PromQL 🔧

Avec Prometheus lancé (partie D du TP), écris et teste les requêtes :

1. Quelles cibles sont **vivantes** ?
2. Le nombre de **connexions actives** à Nginx.
3. Les **requêtes par seconde** sur la dernière minute.
4. Les requêtes par seconde sur **5 minutes** : compare avec la question 3.
5. La **mémoire résidente** du processus Prometheus, en Mo (métrique `process_resident_memory_bytes`).
6. Le nombre de **séries temporelles** actuellement stockées (métrique `prometheus_tsdb_head_series`).

**Questions**
- Pourquoi un intervalle plus long lisse-t-il la courbe ?
- Que renvoie `rate(nginx_http_requests_total[5s])` ? Pourquoi ?
- Que se passe-t-il pour un counter quand l'application redémarre ?

---

## Exercice 9 : Écrire une alerte

Dans le ConfigMap `prometheus-rules`, ajoute une règle `NginxConnexionsElevees` qui se déclenche quand `nginx_connections_active` dépasse **10** pendant **30 secondes**.

1. Écris la règle (nom, `expr`, `for`, labels, annotation).
2. Applique, puis recharge la configuration :
   ```powershell
   kubectl rollout restart deployment/prometheus -n monitoring
   ```
3. Provoque la condition avec plusieurs générateurs de charge (comme à l'étape 12 du TP) et observe l'état dans **Alerts** : inactive, pending, firing.

**Questions**
- À quoi sert le champ `for` ? Que se passerait-il sans lui sur un pic de 2 secondes ?
- Que manque-t-il pour recevoir un message sur ton téléphone ? (Réponse : Alertmanager.)
- Pourquoi une alerte sur « CPU à 80 % » est-elle souvent moins utile qu'une alerte sur le taux d'erreurs ?

---

## Exercice 10 : Un tableau de bord Grafana

1. Déploie Grafana (`manifests/grafana.yaml`) et connecte-toi.
2. Crée un tableau de bord **Nginx** avec **quatre panneaux** :
   - disponibilité (`up`)
   - requêtes par seconde
   - connexions actives
   - un panneau de ton choix (par exemple la mémoire de Prometheus)
3. Change la plage de temps (15 minutes, 1 heure) et l'intervalle de rafraîchissement.
4. Exporte le JSON dans `10-observability/dashboards/`.

**Questions**
- Où Grafana stocke-t-il les métriques ? (Réponse : nulle part, il les interroge.)
- Pourquoi la source de données a-t-elle pu être configurée **sans cliquer** ? Quel est l'intérêt ?
- Pourquoi les tableaux de bord exportés peuvent-ils être versionnés dans Git sans risque ?

---

## Exercice 11 : Observabilité d'une API Spring Boot

Sans copier le cours, écris :

1. les deux dépendances Maven nécessaires
2. les propriétés `application.properties` pour exposer `prometheus` et les probes de santé
3. le bloc `scrape_configs` de Prometheus pour une API `boutique-api` dans le namespace `dev`, port 8080
4. la requête PromQL du **taux d'erreurs 5xx** de l'API
5. la requête du **95e centile de latence**

**Questions**
- Pourquoi ne faut-il pas exposer `/actuator/prometheus` par l'Ingress ?
- Quelle métrique te dit si le pool de connexions à PostgreSQL est saturé ?

---

## Exercice 12 : Une enquête pas à pas 🔍

Scénario : depuis 14 h, les utilisateurs se plaignent que l'API est lente. Le CPU des Pods est normal.

Écris ta démarche, dans l'ordre, avec **l'outil** et **la question** à chaque étape :

1. Quel est le **symptôme** exact ? (Quel signal doré ? Quel tableau de bord ?)
2. Depuis **quand** ? Un déploiement a-t-il eu lieu à ce moment-là ? (Pense à `helm history` ou `kubectl rollout history`.)
3. Les Pods sont-ils **prêts** ? Y a-t-il des **redémarrages** ou des événements anormaux ?
4. Quelle est la **latence** et le **taux d'erreurs** par route ?
5. Que disent les **logs** de l'API sur la période ?
6. La **base de données** est-elle saturée ? (Connexions actives, requêtes lentes.)
7. Une **trace** montrerait quoi ?

**Question :** pourquoi cette démarche est-elle impossible sans métriques historiques ni logs conservés ?

---

## Questions d'auto-évaluation

1. Quels sont les trois piliers de l'observabilité, et que répond chacun ?
2. Pourquoi une application doit-elle écrire ses logs sur stdout/stderr ?
3. Que fait `kubectl logs --previous` ?
4. Quelle différence entre les logs d'une application et les événements Kubernetes ?
5. Pourquoi Prometheus fonctionne-t-il en mode *pull* ? Qu'est-ce qu'un exporter ?
6. Que fait `rate()` et pourquoi est-il indispensable avec un counter ?
7. Qu'est-ce que la cardinalité et pourquoi est-elle dangereuse ?
8. Quelle différence entre Prometheus, Grafana et Alertmanager ?
9. Que signifient les états `pending` et `firing` d'une alerte ?
10. Quels sont les quatre signaux dorés ?
11. Quelle différence entre `kubectl top` et Prometheus ?
12. Pourquoi alerte-t-on sur les symptômes plutôt que sur les causes ?

---

## Nettoyage

```powershell
kubectl delete pod logger crasher charge --ignore-not-found
kubectl delete -f manifests/web-metrics.yaml --ignore-not-found
kubectl delete namespace monitoring --ignore-not-found
kubectl get pods -A
```