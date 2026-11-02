# 10 - Observabilité : logs, métriques, Prometheus et Grafana

> **Objectif du module :** savoir ce qui se passe dans ton cluster et dans tes applications, détecter un problème avant tes utilisateurs, et comprendre pourquoi il est arrivé.

**Durée estimée :** 5 heures · **Prérequis :** modules 01 à 09 terminés, cluster Minikube démarré

---

## 1. Le problème

Un mardi à 3 h du matin, ton API répond lentement. Que fais-tu ?

- Tu sais qu'elle est lente **parce qu'un utilisateur s'est plaint** (trop tard).
- Tu ne sais pas **depuis quand**, ni **si c'est lié** à la dernière mise à jour.
- Le Pod qui avait le problème a été **redémarré** : ses logs ont disparu.
- Tu ne sais pas si c'est le **CPU**, la **mémoire**, la **base de données** ou le **réseau**.

L'**observabilité** est la capacité de comprendre l'état interne d'un système à partir de ce qu'il produit. Elle repose sur trois piliers.

| Pilier | Question à laquelle il répond | Exemple |
|--------|------------------------------|---------|
| **Logs** | Que s'est-il passé, précisément ? | `ERROR paiement refusé pour la commande 4521` |
| **Métriques** | Comment va le système, et comment évolue-t-il ? | 250 requêtes par seconde, 2 % d'erreurs, CPU à 80 % |
| **Traces** | Où le temps est-il passé dans une requête ? | Requête de 900 ms : 800 ms dans la base de données |

> **Monitoring et observabilité :** le monitoring surveille ce que tu as prévu de surveiller (« le CPU dépasse-t-il 90 % ? »). L'observabilité te permet de répondre aussi à des questions que tu n'avais **pas prévues**.

---

## 2. Les logs dans Kubernetes

### Comment ça marche

Une application conteneurisée écrit ses logs sur la **sortie standard** (`stdout`) et la **sortie d'erreur** (`stderr`). Kubernetes les récupère et les stocke dans des fichiers sur le nœud.

```
Application ──stdout/stderr──► fichier de logs sur le nœud ◄── kubectl logs
```

C'est pour cela qu'une application Spring Boot doit **loguer sur la console**, pas dans un fichier à l'intérieur du conteneur.

### Les limites de `kubectl logs`

| Limite | Conséquence |
|--------|-------------|
| Les logs vivent **avec le Pod** | Si le Pod est supprimé, ses logs disparaissent |
| Les logs sont **tournés** (rotation) | Les plus anciens sont effacés quand le fichier devient trop gros |
| Un seul Pod à la fois | Difficile de suivre une requête qui traverse plusieurs services |
| Pas de recherche avancée | Pas de filtre par champ, ni de statistiques |

### Les commandes à connaître

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl logs <pod>` | Logs du Pod |
| `kubectl logs <pod> -c <conteneur>` | Logs d'un conteneur précis (Pod à plusieurs conteneurs) |
| `kubectl logs <pod> -f` | Suit les logs en direct (`Ctrl+C` pour arrêter) |
| `kubectl logs <pod> --tail=50` | Les 50 dernières lignes |
| `kubectl logs <pod> --since=10m` | Les logs des 10 dernières minutes |
| `kubectl logs <pod> --previous` | Logs du conteneur **précédent** (après un crash) |
| `kubectl logs -l app=web` | Logs de tous les Pods portant ce label |
| `kubectl logs <pod> --all-containers --prefix` | Tous les conteneurs, avec leur nom en préfixe |
| `kubectl logs deploy/<nom>` | Logs d'un des Pods du Deployment |

### `--previous` : le réflexe après un crash

Quand un conteneur plante et redémarre (`CrashLoopBackOff`), `kubectl logs` montre le **nouveau** conteneur, souvent vide. L'explication du crash se trouve dans le précédent :

```bash
kubectl logs <pod> --previous
```

### Les événements

Les logs viennent de **l'application**. Les **événements** viennent de **Kubernetes** : ordonnancement, téléchargement d'image, probes en échec, OOMKilled...

```bash
kubectl describe pod <nom>                               # section Events, en bas
kubectl get events --sort-by=.lastTimestamp              # les plus récents en dernier
kubectl get events --field-selector type=Warning         # uniquement les avertissements
```

> Les événements sont **conservés environ une heure**. Si tu enquêtes le lendemain, ils ont disparu : c'est une raison de plus pour centraliser.

### Déboguer avec un conteneur éphémère

Quand l'image de ton application n'a pas d'outils (pas de shell, pas de `curl`), tu peux y **attacher** un conteneur de debug :

```bash
kubectl debug -it <pod> --image=busybox:1.36 --target=<conteneur> -- sh
```

Il partage l'espace de processus du conteneur cible, ce qui te permet de l'inspecter sans modifier son image.

### De bonnes pratiques pour tes logs

| Pratique | Pourquoi |
|----------|----------|
| Écrire sur **stdout/stderr** | C'est ce que Kubernetes collecte |
| Utiliser des **niveaux** (`DEBUG`, `INFO`, `WARN`, `ERROR`) | Filtrer et alerter |
| Format **JSON structuré** | Chaque champ est interrogeable (`niveau`, `service`, `traceId`) |
| Un **identifiant de corrélation** (traceId, requestId) | Suivre une requête à travers plusieurs services |
| **Jamais de secrets** (mots de passe, jetons, numéros de carte) | Les logs sont largement accessibles et conservés |
| Pas de `DEBUG` en production par défaut | Volume, coût, fuite d'informations |

Spring Boot sait produire des logs structurés (par exemple au format ECS) via sa configuration de logging, ce qui évite d'écrire du JSON à la main.

### La collecte centralisée

En production, un **agent** tourne sur chaque nœud (un **DaemonSet**, module 02), lit les fichiers de logs et les envoie vers un **stockage central**.

```
Pods ──► fichiers sur le nœud ──► agent (Fluent Bit, Promtail, Alloy) ──► Loki / Elasticsearch ──► Grafana / Kibana
```

Les logs survivent alors à la mort des Pods, et tu peux les chercher tous ensemble. Cette pile est lourde pour ta connexion : ce module la **décrit** sans l'installer.

---

## 3. Les métriques

Une **métrique** est une **mesure numérique** qui évolue dans le temps : requêtes par seconde, mémoire utilisée, taille d'une file.

### Prometheus

**Prometheus** est le standard de la collecte de métriques dans Kubernetes. Son modèle est particulier : il **tire** les données (*pull*).

```
┌─────────────┐   interroge /metrics toutes les 15 s   ┌──────────────┐
│ Prometheus  │ ─────────────────────────────────────► │ Application  │
│ (stockage)  │ ◄───────────────────────────────────── │ ou exporter  │
└─────────────┘        réponse en texte brut           └──────────────┘
       │
       ▼
   PromQL, alertes, Grafana
```

| Terme | Signification |
|-------|---------------|
| **Target** | Un endpoint à surveiller |
| **Scrape** | Une interrogation d'une target |
| **Job** | Un groupe de targets du même type |
| **Exporter** | Un programme qui **traduit** les statistiques d'un logiciel (Nginx, PostgreSQL, Linux...) au format Prometheus |
| **Série temporelle** | Une valeur mesurée dans le temps, identifiée par un nom et des labels |
| **Rétention** | Durée de conservation des données |

### Le format d'une métrique

Une target expose du texte simple sur `/metrics` :

```
# HELP nginx_connections_active Active client connections
# TYPE nginx_connections_active gauge
nginx_connections_active 3
# HELP nginx_http_requests_total Total http requests
# TYPE nginx_http_requests_total counter
nginx_http_requests_total 1542
```

Chaque métrique a un **nom**, des **labels** (par exemple `{method="GET",status="200"}`) et une **valeur**.

### Les types de métriques

| Type | Comportement | Exemple |
|------|--------------|---------|
| **Counter** | Ne fait que **monter** (ou repart à 0 au redémarrage) | Nombre total de requêtes |
| **Gauge** | Monte et descend | Mémoire utilisée, connexions actives |
| **Histogram** | Répartit les valeurs dans des **tranches** | Durée des requêtes |
| **Summary** | Calcule des quantiles côté application | Rare, on préfère l'histogram |

### PromQL, le langage de requête

| Besoin | Requête |
|--------|---------|
| La cible est-elle vivante ? | `up` |
| Valeur actuelle d'une gauge | `nginx_connections_active` |
| Requêtes **par seconde** (à partir d'un counter) | `rate(nginx_http_requests_total[1m])` |
| Total par service | `sum by (job) (rate(nginx_http_requests_total[1m]))` |
| Taux d'erreurs | `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))` |
| 95e centile de latence | `histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket[5m])))` |
| Mémoire en Mo | `process_resident_memory_bytes / 1024 / 1024` |

> **Règle d'or :** un **counter** brut ne sert presque à rien (il monte indéfiniment). Utilise toujours **`rate()`** pour obtenir une vitesse. L'intervalle (`[1m]`) doit contenir **plusieurs scrapes**.

### La cardinalité, le piège classique

Chaque combinaison de labels crée **une série temporelle**. Un label à valeurs illimitées (identifiant d'utilisateur, URL complète, identifiant de commande) fait **exploser** la mémoire de Prometheus. Garde les labels à **valeurs peu nombreuses** (méthode, code de statut, service).

### Les sources de métriques dans Kubernetes

| Source | Ce qu'elle fournit | Remarque |
|--------|--------------------|----------|
| **metrics-server** | CPU et mémoire **actuels** des Pods et nœuds | Alimente `kubectl top` et le HPA. **Pas d'historique** |
| **cAdvisor** (dans le kubelet) | Métriques détaillées des conteneurs | Collecté par Prometheus |
| **kube-state-metrics** | **État** des objets : Pods prêts ? réplicas disponibles ? | Répond à « combien de Pods sont en `CrashLoopBackOff` ? » |
| **node-exporter** | Métriques des machines (disque, réseau, CPU) | Un par nœud |
| **Ton application** | Métriques **métier et techniques** | Via Actuator/Micrometer pour Spring Boot |

---

## 4. Métriques d'une application Spring Boot

Spring Boot expose ses métriques avec **Actuator** et **Micrometer**.

### Dépendances Maven

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
  <groupId>io.micrometer</groupId>
  <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### Configuration

```properties
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.health.probes.enabled=true
management.metrics.tags.application=boutique-api
```

L'endpoint **`/actuator/prometheus`** expose alors toutes les métriques. Le même Actuator fournit les endpoints de probes du module 06 (`/actuator/health/liveness`, `/readiness`).

### Déclarer la target dans Prometheus

```yaml
- job_name: boutique-api
  metrics_path: /actuator/prometheus
  static_configs:
    - targets: ["api.dev.svc.cluster.local:8080"]
```

### Les métriques utiles d'une API Java

| Métrique | Ce qu'elle indique |
|----------|--------------------|
| `http_server_requests_seconds_*` | Nombre et durée des requêtes HTTP, par URI et statut |
| `jvm_memory_used_bytes` | Mémoire de la JVM (heap, metaspace) |
| `jvm_gc_pause_seconds_*` | Pauses du ramasse-miettes |
| `hikaricp_connections_active` | Connexions actives vers la base de données |
| `process_cpu_usage` | Utilisation CPU du processus |
| `jvm_threads_live_threads` | Nombre de threads |

> ⚠️ N'expose pas `/actuator/*` à Internet. Garde-le **interne** au cluster (pas dans l'Ingress), ou sur un port de gestion séparé (`management.server.port`).

---

## 5. Grafana : visualiser

**Grafana** affiche tes données sous forme de **tableaux de bord**. Il ne stocke pas les métriques : il les **interroge** auprès de sources de données (Prometheus, Loki...).

| Concept | Signification |
|---------|---------------|
| **Data source** | Une source de données (ici Prometheus) |
| **Dashboard** | Une page composée de panneaux |
| **Panel** | Un graphique, un chiffre, une jauge, alimenté par une requête PromQL |
| **Variable** | Un filtre réutilisable (choisir le namespace ou le Pod) |
| **Explore** | Un mode d'exploration libre, pour tester des requêtes |

Le **provisioning** déclare la source de données dans un fichier au démarrage : c'est ce que fait notre `grafana.yaml`, sans clic dans l'interface (« infrastructure as code »).

---

## 6. L'alerting

Un tableau de bord ne te réveille pas à 3 h du matin : une **alerte** si.

### Une règle Prometheus

Fichier [`manifests/prometheus.yaml`](./manifests/prometheus.yaml) (ConfigMap `prometheus-rules`) :

```yaml
- alert: WebDown
  expr: up{job="web-metrics"} == 0      # la condition
  for: 1m                               # doit rester vraie 1 minute
  labels:
    severity: critical
  annotations:
    summary: "La cible {{ $labels.instance }} ne répond plus"
```

| Champ | Rôle |
|-------|------|
| `expr` | Expression PromQL : l'alerte est active quand elle renvoie un résultat |
| `for` | Durée avant déclenchement : évite les fausses alertes sur un pic bref |
| `labels` | Étiquettes (gravité...) pour le routage |
| `annotations` | Description lisible, lien vers une procédure |

Une alerte passe par les états **inactive**, **pending** (condition vraie mais `for` pas écoulé), puis **firing**.

### Alertmanager

Prometheus **détecte**, **Alertmanager** **notifie** : il regroupe les alertes, évite les doublons, gère les silences et envoie vers un e-mail, Slack, PagerDuty... Ce module installe seulement Prometheus (les alertes se voient dans son interface) pour limiter les téléchargements.

### Quoi surveiller : les 4 signaux dorés

| Signal | Question | Exemple |
|--------|----------|---------|
| **Latence** | Combien de temps prend une requête ? | 95e centile de durée |
| **Trafic** | Quelle charge ? | Requêtes par seconde |
| **Erreurs** | Quelle part échoue ? | Taux de réponses 5xx |
| **Saturation** | Les ressources sont-elles presque pleines ? | Mémoire, CPU, pool de connexions |

Variantes : **RED** (Rate, Errors, Duration) pour les services, **USE** (Utilization, Saturation, Errors) pour les ressources.

### Les bonnes pratiques d'alerting

| ✅ À faire | ❌ À éviter |
|-----------|------------|
| Alerter sur les **symptômes** vus par l'utilisateur (erreurs, lenteur) | Alerter sur chaque cause possible (CPU à 70 %) |
| Chaque alerte est **actionnable** | Des alertes dont personne ne sait que faire |
| Un lien vers une **procédure** (runbook) | Des alertes mystérieuses |
| Peu d'alertes **pertinentes** | Un flot de bruit qu'on finit par ignorer |
| Définir des **objectifs** (SLO : 99,5 % de requêtes réussies) | Des seuils arbitraires |

---

## 7. Les traces, en deux mots

Dans une architecture à plusieurs services, une requête passe par l'API, un service de paiement, la base de données... Une **trace** suit cette requête de bout en bout, avec la durée de chaque étape (appelée **span**).

- Le standard est **OpenTelemetry** (collecte) avec **Tempo** ou **Jaeger** (stockage et visualisation).
- Le **traceId** est ajouté aux logs : tu retrouves tous les logs d'une même requête.
- Utile dès que tu as **plusieurs services** qui s'appellent entre eux. Pour une seule API, logs et métriques suffisent au début.

---

## 8. Et en production ?

Ce module installe Prometheus et Grafana **à la main**, avec de simples manifests : c'est léger et pédagogique. En production, on utilise plutôt :

| Outil | Rôle |
|-------|------|
| **kube-prometheus-stack** (chart Helm) | Prometheus + Alertmanager + Grafana + exporters + dashboards, gérés par un **operator** |
| **ServiceMonitor** | Un objet Kubernetes qui dit à l'operator « scrape ce Service », sans modifier la config de Prometheus |
| **Loki + Alloy/Promtail** | Logs centralisés, intégrés à Grafana |
| **Tempo** | Traces |
| **Services managés** (Grafana Cloud, Datadog, CloudWatch...) | Tout hébergé |

> ⚠️ `kube-prometheus-stack` télécharge **de nombreuses images** (plusieurs centaines de Mo). Avec ta connexion actuelle, garde-le pour plus tard.

---

## 9. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl logs <pod> -c <conteneur> --tail=50` | Dernières lignes d'un conteneur |
| `kubectl logs <pod> --previous` | Logs du conteneur précédent |
| `kubectl logs -l app=<nom> --all-containers --prefix` | Logs de plusieurs Pods |
| `kubectl get events --sort-by=.lastTimestamp` | Événements récents |
| `kubectl debug -it <pod> --image=busybox:1.36 --target=<c> -- sh` | Conteneur de debug éphémère |
| `kubectl top nodes` / `kubectl top pods -A` | CPU et mémoire actuels (metrics-server) |
| `kubectl port-forward svc/<nom> <local>:<port>` | Accès local à un service |
| `kubectl port-forward svc/<nom> 8080:80 9113:9113` | Plusieurs ports d'un coup |
| `minikube addons enable metrics-server` | Active `kubectl top` |

---

## 10. Pratique

> ⚠️ **Avec ta connexion lente, ce module est le plus lourd.** Il est découpé en quatre parties, de la plus légère à la plus lourde. **Chaque partie est utile seule** : arrête-toi quand ta connexion ne suit plus.
>
> | Partie | Contenu | Téléchargement |
> |--------|---------|----------------|
> | A | Logs, événements, debug | **Aucun** (`busybox` est déjà là) |
> | B | `kubectl top` | Petit (metrics-server, environ 25 Mo, si pas déjà installé) |
> | C | Nginx + exporter, lecture des métriques brutes | Petit (exporter, quelques dizaines de Mo) |
> | D | Prometheus et Grafana | **Gros** : environ 100 Mo pour Prometheus et 200 Mo pour Grafana (vérifie les tailles sur Docker Hub). Compte **une heure** à ton débit |
>
> 💡 **Astuce pour la partie D :** télécharge les images en tâche de fond avec Docker, qui reprend les couches interrompues, puis charge-les dans Minikube :
> ```powershell
> docker pull prom/prometheus:v3.1.0
> docker pull grafana/grafana:11.4.0
> minikube image load prom/prometheus:v3.1.0
> minikube image load grafana/grafana:11.4.0
> ```
> Lance ces commandes avant de commencer, et fais les parties A à C pendant l'attente.
>
> Les fichiers ont été vérifiés (`kubeconform` sur les manifests, `promtool` sur la configuration Prometheus), mais **pas exécutés sur ton cluster**. Si une image ou un tag n'existe plus, cherche le dernier tag sur Docker Hub et dis-le-moi.

Commandes pour **PowerShell**, depuis le dossier du module.

## Partie A : Logs, événements, debug

### Étape 1 : Un Pod qui écrit des logs

```powershell
kubectl apply -f manifests/logger.yaml
kubectl get pod logger
kubectl logs logger
```

Le Pod a **deux conteneurs** : kubectl choisit le premier et le signale. Choisis-en un :

```powershell
kubectl logs logger -c api --tail=20
kubectl logs logger -c worker --tail=5
kubectl logs logger --all-containers --prefix --tail=5
```

### Étape 2 : Filtrer et suivre

```powershell
kubectl logs logger -c api --since=1m
kubectl logs logger -c api | Select-String "ERROR"
kubectl logs logger -c api | Select-String "WARN|ERROR"
kubectl logs -l app=logger --all-containers --tail=3
kubectl logs logger -c api -f
```

Le dernier suit les logs en direct : arrête avec `Ctrl+C`. `Select-String` joue le rôle de `grep` sous PowerShell.

### Étape 3 : Comprendre un crash avec `--previous`

```powershell
kubectl apply -f manifests/crasher.yaml
kubectl get pod crasher -w
```

Attends que le statut passe à `CrashLoopBackOff` (`Ctrl+C` pour quitter l'observation), puis :

```powershell
kubectl logs crasher
kubectl logs crasher --previous
kubectl describe pod crasher
```

Dans `describe`, repère `Last State: Terminated`, `Exit Code: 1`, et le compteur `Restart Count`. Le message d'erreur (`connexion refusée`) est dans les logs.

### Étape 4 : Les événements

```powershell
kubectl get events --sort-by=.lastTimestamp
kubectl get events --field-selector type=Warning
```

Repère les événements `BackOff` liés à `crasher`.

### Étape 5 : Un conteneur de debug éphémère

```powershell
kubectl debug -it logger --image=busybox:1.36 --target=api -- sh
```

Dans le shell du conteneur de debug :

```sh
ps
exit
```

Tu vois les processus du conteneur `api`. Un conteneur éphémère ne peut pas être retiré : il disparaît avec le Pod.

### Étape 6 : Nettoyer

```powershell
kubectl delete pod logger crasher
```

## Partie B : `kubectl top`

Si tu as déjà installé le metrics-server au module 06, passe l'activation.

```powershell
minikube addons enable metrics-server
kubectl top nodes
kubectl top pods -A
kubectl top pods -A --sort-by=memory
```

Attends environ une minute après l'activation. Tu vois l'état **actuel**, **sans historique** et **sans alerte** : c'est exactement ce que Prometheus ajoute.

## Partie C : Métriques brutes

### Étape 7 : Déployer Nginx avec son exporter

```powershell
kubectl apply -f manifests/web-metrics.yaml
kubectl get pods -l app=web-metrics -w
```

Attends `2/2 Running` : un conteneur `nginx` et un conteneur `exporter` dans le même Pod (le **sidecar**).

### Étape 8 : Lire les métriques

Ouvre l'accès aux deux ports dans un terminal (laisse-le ouvert) :

```powershell
kubectl port-forward svc/web-metrics 8080:80 9113:9113
```

Dans un **autre** terminal :

```powershell
curl.exe -s http://localhost:9113/metrics | Select-String "^nginx_"
```

Tu lis le format texte de Prometheus : `nginx_up`, `nginx_connections_active`, `nginx_http_requests_total`.

### Étape 9 : Voir un counter monter

```powershell
curl.exe -s http://localhost:9113/metrics | Select-String "nginx_http_requests_total"
1..30 | ForEach-Object { curl.exe -s http://localhost:8080 | Out-Null }
curl.exe -s http://localhost:9113/metrics | Select-String "nginx_http_requests_total"
```

Le compteur a augmenté d'**au moins 30**. Il ne fait que monter : c'est ce qui justifie `rate()`.

## Partie D : Prometheus et Grafana

### Étape 10 : Déployer Prometheus

```powershell
kubectl apply -f manifests/prometheus.yaml
kubectl get pods -n monitoring -w
```

Attends `1/1 Running` (le téléchargement de l'image prend du temps). Puis :

```powershell
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Ouvre http://localhost:9090 dans ton navigateur.

### Étape 11 : Explorer Prometheus

- **Status → Targets** : `web-metrics` doit être **UP** (il vient de la partie C, qui doit tourner).
- **Graph** : saisis ces requêtes l'une après l'autre, puis **Execute** :

```
up
nginx_connections_active
nginx_http_requests_total
rate(nginx_http_requests_total[1m])
```

- **Alerts** : tu vois tes deux règles, `WebDown` et `WebTrafficEleve`, **inactive**.

### Étape 12 : Déclencher une alerte

Génère du trafic depuis un Pod :

```powershell
kubectl run charge --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://web-metrics > /dev/null; done'
```

Dans Prometheus, refais `rate(nginx_http_requests_total[1m])` : la valeur monte. Dans **Alerts**, `WebTrafficEleve` passe à **pending** puis **firing** après environ 1 minute. Arrête la charge :

```powershell
kubectl delete pod charge
```

L'alerte revient à **inactive**.

### Étape 13 : Provoquer une panne

```powershell
kubectl scale deployment web-metrics --replicas=0
```

Dans **Status → Targets**, la cible passe à **DOWN**, et `WebDown` devient **firing** après 1 minute. Rétablis :

```powershell
kubectl scale deployment web-metrics --replicas=1
```

### Étape 14 : Déployer Grafana

```powershell
kubectl apply -f manifests/grafana.yaml
kubectl get pods -n monitoring -w
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Ouvre http://localhost:3000. Connexion : utilisateur `admin`, mot de passe `motdepasse-exemple` (faux, défini dans le manifest).

### Étape 15 : Construire un tableau de bord

1. **Connections → Data sources** : `Prometheus` est déjà configurée (provisioning).
2. **Dashboards → New → New dashboard → Add visualization**, choisis `Prometheus`.
3. Crée trois panneaux avec ces requêtes :
   - `nginx_connections_active` (connexions actives)
   - `rate(nginx_http_requests_total[1m])` (requêtes par seconde)
   - `up` (disponibilité)
4. Enregistre le tableau de bord, relance la charge de l'étape 12 et regarde le panneau réagir.
5. **Exporte-le** (Share → Export → Save to file) et place le JSON dans `10-observability/dashboards/` : il est versionnable dans Git, et il ne contient pas de secret.

### Étape 16 : Nettoyer

```powershell
kubectl delete pod charge --ignore-not-found
kubectl delete namespace monitoring
kubectl delete -f manifests/web-metrics.yaml
```

---

## 11. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `kubectl logs` : `a container name must be specified` | Pod à plusieurs conteneurs | Ajoute `-c <conteneur>` |
| `kubectl logs` vide après un crash | Tu lis le **nouveau** conteneur | Utilise `--previous` |
| Logs introuvables après suppression du Pod | Logs liés au Pod | Centralise-les (Loki, Elasticsearch) |
| `kubectl top` : `Metrics API not available` | metrics-server absent ou pas encore prêt | `minikube addons enable metrics-server`, attends 1 à 2 minutes |
| Pod `web-metrics` en `1/2` | Le sidecar `exporter` ne démarre pas | `kubectl logs <pod> -c exporter` ; vérifie le tag de l'image |
| Target Prometheus `DOWN` | Mauvais nom de Service ou de port, ou Pod absent | Vérifie `web-metrics.default.svc.cluster.local:9113` |
| `ImagePullBackOff` sur Prometheus ou Grafana | Image lourde, connexion lente ou tag inexistant | Pré-télécharge avec `docker pull` puis `minikube image load` |
| Pod Prometheus en `OOMKilled` | Limite mémoire trop basse | Augmente `limits.memory` |
| Grafana : `No data` | Mauvaise requête, ou mauvaise plage de temps | Teste la requête dans Prometheus ; règle la période en haut à droite |
| `rate()` renvoie `No data` | Intervalle trop court (moins de 2 scrapes) | Utilise au moins `[1m]` pour un scrape toutes les 15 s |
| Alerte qui ne se déclenche jamais | `for` trop long, ou expression toujours fausse | Teste `expr` dans Graph ; regarde l'état dans Alerts |
| Prometheus consomme toute la mémoire | Labels à cardinalité élevée | Évite les identifiants uniques dans les labels |
| Mot de passe Grafana exposé dans Git | Secret commité | Utilise un vrai Secret hors Git, et change le mot de passe |

---

## 12. Points clés à retenir

- L'observabilité repose sur **trois piliers** : **logs** (ce qui s'est passé), **métriques** (comment ça évolue), **traces** (où le temps passe).
- Dans Kubernetes, les applications loguent sur **stdout/stderr** ; `kubectl logs` lit ces fichiers, qui disparaissent avec le Pod.
- Après un crash, **`--previous`** donne les logs du conteneur précédent. Les **événements** (`describe`, `get events`) racontent ce que Kubernetes a fait.
- **Prometheus** tire (*pull*) les métriques sur `/metrics`. Un **exporter** traduit un logiciel existant ; **Actuator + Micrometer** le fait pour Spring Boot.
- Utilise toujours **`rate()`** sur un counter. Évite les labels à **cardinalité** élevée.
- **Grafana** visualise, **Alertmanager** notifie. Alerte sur les **symptômes** (erreurs, lenteur), de façon **actionnable**.
- Les **4 signaux dorés** : latence, trafic, erreurs, saturation.
- `kubectl top` montre l'état actuel sans historique ; Prometheus garde l'historique et permet les alertes.
- En production, on utilise souvent **kube-prometheus-stack**, **Loki** et **Tempo**, ou un service managé.

## ✅ Checklist

- [ ] Je sais citer les trois piliers de l'observabilité et leur rôle
- [ ] Je sais lire les logs d'un Pod à plusieurs conteneurs, avec `--tail`, `--since` et `-f`
- [ ] Je sais diagnostiquer un crash avec `--previous`, `describe` et les événements
- [ ] Je sais expliquer pourquoi les logs doivent être centralisés en production
- [ ] Je sais expliquer le modèle *pull* de Prometheus et le rôle d'un exporter
- [ ] Je sais distinguer counter, gauge et histogram, et j'utilise `rate()` sur un counter
- [ ] Je sais écrire une règle d'alerte avec `expr` et `for`
- [ ] Je sais configurer Actuator et Micrometer pour une API Spring Boot
- [ ] Je connais les quatre signaux dorés
- [ ] J'ai construit un tableau de bord Grafana simple

---

## 🎓 Fin de la feuille de route

Tu as maintenant parcouru les dix modules : fondamentaux, workloads, réseau, configuration, stockage, santé et ressources, organisation, Helm et Kustomize, CI/CD, observabilité.

**Étape suivante :** le [projet fil rouge](../project/README.md) : une application **Spring Boot + PostgreSQL + Angular** déployée de bout en bout avec tout ce que tu as appris (Deployments, Services, ConfigMaps et Secrets, StatefulSet, probes, Kustomize ou Helm, pipeline GitHub Actions, métriques Prometheus).