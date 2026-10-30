# 06 - Santé et ressources : probes, requests/limits et autoscaling

> **Objectif du module :** permettre à Kubernetes de savoir si ton application va bien, lui dire de quelles ressources elle a besoin, et la faire grandir automatiquement sous la charge.

**Durée estimée :** 4 heures · **Prérequis :** modules 01 à 05 terminés, cluster Minikube démarré

---

## 1. Le problème

Pour Kubernetes, un conteneur « en bonne santé » est par défaut un conteneur **dont le processus tourne**. Or une application peut être :

- **démarrée mais pas encore prête** : une API Spring Boot met 20 à 60 secondes à démarrer, et reçoit déjà du trafic
- **vivante mais bloquée** : un deadlock, une file saturée, un processus qui tourne sans plus rien répondre
- **gourmande** : une fuite mémoire qui fait tomber le nœud et les voisins

Il faut donc deux choses :

| Besoin | Mécanisme |
|--------|-----------|
| Dire **si l'application va bien** | Les **probes** (sondes de santé) |
| Dire **ce dont elle a besoin** et lui fixer des limites | Les **requests** et **limits** |
| L'adapter à la **charge** | L'**autoscaling** (HPA) |

---

## 2. Les probes

Une **probe** est un test que le **kubelet** exécute régulièrement sur un conteneur. Il existe trois sortes, avec trois rôles très différents.

| Probe | Question posée | Si elle échoue |
|-------|----------------|----------------|
| **readiness** | « Es-tu prêt à recevoir du trafic ? » | Le Pod est **retiré du Service** (aucun redémarrage) |
| **liveness** | « Es-tu encore vivant ? » | Le conteneur est **redémarré** |
| **startup** | « As-tu fini de démarrer ? » | Le conteneur est redémarré, et les autres probes sont **suspendues** tant qu'elle n'a pas réussi |

### Les trois méthodes de test

| Méthode | Principe | Exemple |
|---------|----------|---------|
| `httpGet` | Une requête HTTP : succès si le code est entre 200 et 399 | `GET /actuator/health` |
| `tcpSocket` | Ouvre une connexion TCP : succès si le port répond | Base de données sur 5432 |
| `exec` | Exécute une commande dans le conteneur : succès si elle renvoie 0 | `pg_isready` |

(Il existe aussi une probe `grpc` pour les services gRPC.)

### Les paramètres

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 3     # attendre avant la première vérification
  periodSeconds: 5           # fréquence des vérifications
  timeoutSeconds: 1          # temps maximum de réponse
  failureThreshold: 3        # échecs consécutifs avant de décider
  successThreshold: 1        # succès consécutifs pour redevenir sain
```

Avec `periodSeconds: 5` et `failureThreshold: 3`, Kubernetes décide qu'il y a un problème après environ **15 secondes**.

### Readiness, ce que ça change concrètement

```
Service web-sante
 ├── Pod 1  Ready ✅        ← reçoit du trafic
 ├── Pod 2  Ready ✅        ← reçoit du trafic
 └── Pod 3  NotReady ❌     ← retiré des Endpoints, aucun trafic
```

C'est le lien avec le module 03 : un Pod **non prêt** n'apparaît pas dans les Endpoints du Service. C'est aussi ce qui rend les **mises à jour progressives** sûres (module 02) : Kubernetes n'enlève un ancien Pod qu'une fois le nouveau **prêt**.

### Liveness, ce qu'il faut éviter

Une liveness probe mal pensée peut provoquer des **catastrophes en chaîne** :

| ❌ À éviter | ✅ À faire |
|-------------|-----------|
| Faire dépendre la liveness de la **base de données** : si la base tombe, **tous** les Pods sont redémarrés en boucle | Tester uniquement que **l'application elle-même** répond |
| Un délai trop court : l'application est tuée pendant son démarrage | Utiliser une **startup probe** ou un `initialDelaySeconds` suffisant |
| Une liveness identique à la readiness avec des seuils serrés | Une liveness **plus tolérante** que la readiness |

### Startup probe, pour les démarrages lents (Spring Boot)

```yaml
startupProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  periodSeconds: 5
  failureThreshold: 30      # 30 x 5 s = 150 s maximum pour démarrer
```

Tant que la startup probe n'a pas réussi, ni la liveness ni la readiness ne s'exécutent. Ensuite, la liveness peut être serrée sans risque de tuer une application encore en train de démarrer.

### Spring Boot et Actuator

Spring Boot fournit les bons endpoints avec **Actuator** :

```properties
management.endpoint.health.probes.enabled=true
management.endpoints.web.exposure.include=health
```

| Endpoint | Utilisation |
|----------|-------------|
| `/actuator/health/liveness` | Liveness et startup probes |
| `/actuator/health/readiness` | Readiness probe |

Un exemple complet est dans [`manifests/spring-boot-probes.yaml`](./manifests/spring-boot-probes.yaml).

---

## 3. Requests et limits

Chaque conteneur peut déclarer ses besoins en **CPU** et en **mémoire** :

```yaml
resources:
  requests:            # ce qui est RÉSERVÉ (garanti)
    cpu: 250m
    memory: 512Mi
  limits:              # le PLAFOND à ne pas dépasser
    cpu: 500m
    memory: 1Gi
```

| | `requests` | `limits` |
|---|-----------|----------|
| Rôle | Quantité **réservée** | Quantité **maximale** |
| Utilisé par | Le **scheduler** pour choisir le nœud | Le **kubelet** et le noyau, à l'exécution |
| Si absent | Aucune garantie | Aucun plafond |

### Les unités

| Ressource | Unité | Exemples |
|-----------|-------|----------|
| **CPU** | Cœurs, ou **millicores** (`m`) | `1` = 1 cœur, `500m` = 0,5 cœur, `100m` = 0,1 cœur |
| **Mémoire** | Octets avec suffixe | `128Mi`, `512Mi`, `1Gi` |

⚠️ Ne confonds pas `Mi` (mébioctet, binaire) et `M` (mégaoctet, décimal). Utilise `Mi` et `Gi`.

### Que se passe-t-il quand on dépasse ?

| Ressource | Dépassement de la limite | Conséquence |
|-----------|--------------------------|-------------|
| **CPU** | Le conteneur est **ralenti** (throttling) | Application plus lente, **jamais tuée** |
| **Mémoire** | Le conteneur est **tué** | **`OOMKilled`**, code de sortie `137`, puis redémarrage |

La mémoire est **non compressible** : on ne peut pas « ralentir » une mémoire pleine, on tue donc le processus.

### Quand le scheduler ne trouve pas de place

Si la somme des `requests` demandées dépasse ce qui reste sur les nœuds, le Pod reste en **`Pending`** :

```
Warning  FailedScheduling  0/1 nodes are available: 1 Insufficient memory.
```

### Classes de QoS

Kubernetes classe chaque Pod selon ses ressources déclarées. En cas de pénurie sur un nœud, il **évince** d'abord les moins prioritaires :

| Classe | Condition | Éviction |
|--------|-----------|----------|
| **Guaranteed** | `requests` = `limits` pour CPU **et** mémoire, sur tous les conteneurs | En dernier |
| **Burstable** | Au moins un `requests` ou `limits` défini, mais pas égaux | Au milieu |
| **BestEffort** | Aucune ressource déclarée | **En premier** |

```bash
kubectl get pod <nom> -o jsonpath='{.status.qosClass}'
```

### Conseils pour une API Java

| Conseil | Pourquoi |
|---------|----------|
| Toujours définir `requests` **et** une limite mémoire | Évite un Pod gourmand qui écrase les autres |
| Limite mémoire **supérieure au heap** | La JVM utilise aussi du métaspace, des threads, des buffers |
| `-XX:MaxRAMPercentage=75` | La JVM dimensionne son heap selon la limite du conteneur |
| Mémoire : `requests` = `limits` | Évite les `OOMKilled` surprises |
| CPU : souvent une `request` sans `limit` | Une limite CPU trop basse ralentit le démarrage de la JVM (débat courant, à adapter) |

---

## 4. L'autoscaling horizontal (HPA)

Le **HorizontalPodAutoscaler** ajuste automatiquement le **nombre de réplicas** d'un Deployment selon la charge.

```
Charge ↑  →  CPU moyen > 50 %  →  HPA ajoute des Pods
Charge ↓  →  CPU moyen < 50 %  →  HPA retire des Pods (avec délai)
```

### La formule

```
réplicas souhaités = ceil( réplicas actuels × (métrique actuelle / métrique cible) )
```

Exemple : 2 Pods à **90 %** de CPU avec une cible de **50 %** donne ceil(2 × 90/50) = **4 Pods**.

### Manifest

Fichier [`manifests/hpa.yaml`](./manifests/hpa.yaml) :

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-hpa
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

### Deux prérequis

1. Le **metrics-server** doit être installé (il fournit les mesures CPU et mémoire).
2. Les Pods doivent avoir des **`requests`** : le pourcentage est calculé **par rapport à la requête CPU**. Sans `requests`, le HPA ne peut rien calculer.

### Comportement

| Aspect | Valeur par défaut |
|--------|-------------------|
| Montée en charge | Rapide (quelques dizaines de secondes) |
| Descente | **Lente** : fenêtre de stabilisation de **5 minutes**, pour éviter les va-et-vient |
| Fréquence de vérification | Environ toutes les 15 secondes |

### Autres types d'autoscaling

| Outil | Rôle |
|-------|------|
| **HPA** | Plus ou moins de **Pods** (ce module) |
| **VPA** | Ajuste les **requests/limits** d'un Pod |
| **Cluster Autoscaler** | Ajoute ou retire des **nœuds** (cloud) |
| **KEDA** | Autoscaling sur des événements (file de messages, etc.) |

---

## 5. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl describe pod <nom>` | Probes, ressources, `Last State`, événements d'échec |
| `kubectl get pods` | Colonne `READY` (`1/1` = prêt) et `RESTARTS` |
| `kubectl top pods` / `kubectl top nodes` | Consommation CPU/mémoire (metrics-server requis) |
| `kubectl describe node minikube` | Ressources allouées et disponibles sur le nœud |
| `kubectl get pod <nom> -o jsonpath='{.status.qosClass}'` | Classe de QoS |
| `kubectl get hpa` / `kubectl get hpa -w` | État de l'autoscaler |
| `kubectl autoscale deployment <nom> --cpu-percent=50 --min=1 --max=5` | Crée un HPA (impératif) |
| `minikube addons enable metrics-server` | Installe le metrics-server |
| `kubectl get events --sort-by=.lastTimestamp` | Derniers événements du cluster |

---

## 6. Pratique

> ⚠️ **Avec ta connexion lente :** les étapes 1 à 6 n'utilisent que `nginx:1.27` et `busybox:1.36`, déjà chez toi. **L'étape 7 (autoscaling) est optionnelle** : elle demande d'installer le **metrics-server**, ce qui télécharge une petite image depuis `registry.k8s.io` (environ 25 Mo compressés). Fais-la quand ta connexion est bonne.

Commandes pour **PowerShell**, depuis le dossier du module.

### Étape 1 : Déployer avec probes et ressources

```powershell
kubectl apply -f manifests/deployment-probes.yaml
kubectl get pods
kubectl describe pod -l app=web-sante
```

Dans `describe`, repère les lignes `Liveness`, `Readiness`, `Limits`, `Requests` et `QoS Class` (ici **Burstable**, car `requests` et `limits` diffèrent).

### Étape 2 : Casser la readiness probe

Ouvre **deux terminaux**. Dans le premier :

```powershell
kubectl get pods -w
```

Dans le second :

```powershell
kubectl apply -f manifests/deployment-readiness-cassee.yaml
kubectl rollout status deployment/web-sante
```

Observe : les nouveaux Pods sont `Running` mais restent en **`0/1`** (non prêts), alors que les anciens sont toujours `1/1`. La mise à jour est **bloquée**, mais l'application continue à répondre. Fais `Ctrl+C` sur `rollout status`, puis examine la cause :

```powershell
kubectl describe pod <nouveau-pod>
kubectl get endpointslices -l kubernetes.io/service-name=web-sante
```

Dans les Events : `Readiness probe failed: HTTP probe failed with statuscode: 404`. Les Pods non prêts n'apparaissent pas dans les Endpoints. Reviens en arrière :

```powershell
kubectl rollout undo deployment/web-sante
kubectl rollout status deployment/web-sante
```

### Étape 3 : Provoquer des redémarrages avec la liveness probe

```powershell
kubectl apply -f manifests/pod-liveness.yaml
kubectl get pod liveness-demo -w
```

Après environ 45 secondes, la colonne `RESTARTS` passe à `1` : le fichier `/tmp/healthy` a disparu, la probe a échoué, et Kubernetes a redémarré le conteneur. Dans un autre terminal :

```powershell
kubectl describe pod liveness-demo
```

Lis les Events : `Liveness probe failed: cat: can't open '/tmp/healthy'` puis `Killing`.

### Étape 4 : Voir les ressources du nœud

```powershell
kubectl describe node minikube
```

Descends jusqu'à `Allocated resources` : tu vois la somme des `requests` et des `limits` des Pods, en pourcentage de la capacité du nœud. C'est ce que le scheduler consulte pour placer un nouveau Pod.

### Étape 5 : Provoquer un OOMKilled

```powershell
kubectl apply -f manifests/pod-oom.yaml
kubectl get pod oom-demo -w
```

Le Pod passe en `OOMKilled` puis `CrashLoopBackOff`. Pour confirmer :

```powershell
kubectl describe pod oom-demo
```

Dans `Last State`, tu lis `Reason: OOMKilled` et `Exit Code: 137`.

### Étape 6 : Provoquer un Pod Pending

```powershell
kubectl apply -f manifests/pod-trop-gros.yaml
kubectl get pod trop-gros
kubectl describe pod trop-gros
```

Le Pod reste `Pending`. Dans les Events : `FailedScheduling ... Insufficient cpu / Insufficient memory`. Le scheduler ne trouve aucun nœud avec 50 CPU et 100 Gi disponibles.

### Étape 7 (optionnelle) : Autoscaling

**7a. Installer le metrics-server**

```powershell
minikube addons enable metrics-server
kubectl get pods -n kube-system
```

Attends que `metrics-server-...` soit `Running`, puis environ une minute de plus, et vérifie :

```powershell
kubectl top nodes
kubectl top pods
```

**7b. Déployer l'application et l'autoscaler**

```powershell
kubectl apply -f manifests/deployment-hpa.yaml
kubectl apply -f manifests/hpa.yaml
kubectl get hpa
```

**7c. Générer de la charge** (dans un terminal à part pour suivre le HPA) :

```powershell
kubectl get hpa -w
```

Dans un autre terminal, lance trois générateurs de charge :

```powershell
kubectl run charge1 --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://web-hpa > /dev/null; done'
kubectl run charge2 --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://web-hpa > /dev/null; done'
kubectl run charge3 --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://web-hpa > /dev/null; done'
```

En 1 à 3 minutes, la colonne `TARGETS` dépasse 50 % et `REPLICAS` monte (jusqu'à 5). Vérifie avec `kubectl get pods -l app=web-hpa`.

**7d. Arrêter la charge et observer la descente**

```powershell
kubectl delete pod charge1 charge2 charge3
```

Le nombre de réplicas redescend **lentement** (fenêtre de stabilisation, réduite à 60 s dans notre manifest).

### Étape 8 : Nettoyer

```powershell
kubectl delete -f manifests/hpa.yaml --ignore-not-found
kubectl delete -f manifests/deployment-hpa.yaml --ignore-not-found
kubectl delete -f manifests/deployment-probes.yaml
kubectl delete pod liveness-demo oom-demo trop-gros charge1 charge2 charge3 --ignore-not-found
```

---

## 7. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| Pod `Running` mais `0/1` | Readiness probe en échec | `kubectl describe pod`, lis `Readiness probe failed` |
| `RESTARTS` qui monte sans cesse | Liveness en échec, ou crash applicatif | `describe` puis `kubectl logs --previous` |
| `CrashLoopBackOff` avec `OOMKilled` | Limite mémoire trop basse | Augmente la limite, ou corrige la fuite mémoire |
| Application Java tuée au démarrage | Liveness trop agressive pour une JVM lente | Ajoute une **startup probe** |
| Pod `Pending` avec `Insufficient cpu/memory` | `requests` trop élevées pour le nœud | Réduis les `requests` ou ajoute des nœuds |
| `kubectl top` répond `Metrics API not available` | metrics-server absent ou pas encore prêt | `minikube addons enable metrics-server`, patiente 1 à 2 min |
| HPA affiche `<unknown>` dans `TARGETS` | metrics-server absent, ou Pods sans `requests` | Installe-le et ajoute des `requests` |
| Tous les Pods redémarrent quand la base tombe | Liveness qui dépend de la base de données | Ne teste que l'application elle-même |
| Application lente sans erreur | Limite CPU trop basse (throttling) | Augmente ou retire la limite CPU |

---

## 8. Points clés à retenir

- **Readiness** : prêt à recevoir du trafic (échec = retiré du Service). **Liveness** : vivant (échec = redémarré). **Startup** : démarrage lent.
- Une liveness probe ne doit **jamais** dépendre d'une base de données ou d'un service externe.
- **`requests`** = réservé, utilisé pour **placer** le Pod. **`limits`** = plafond, appliqué à **l'exécution**.
- Dépasser la limite **CPU** ralentit le conteneur. Dépasser la limite **mémoire** le **tue** (`OOMKilled`, code 137).
- Trois classes de QoS : **Guaranteed**, **Burstable**, **BestEffort** : l'ordre d'éviction en cas de pénurie.
- Le **HPA** adapte le nombre de réplicas, mais exige un **metrics-server** et des **`requests`**.
- Pour Spring Boot : **Actuator** (`/actuator/health/liveness` et `/readiness`), `-XX:MaxRAMPercentage=75` et une limite mémoire supérieure au heap.

## ✅ Checklist

- [ ] Je sais distinguer readiness, liveness et startup, et ce que chacune déclenche
- [ ] Je sais écrire une probe `httpGet` avec ses paramètres
- [ ] Je sais pourquoi une liveness ne doit pas tester la base de données
- [ ] Je sais expliquer la différence entre `requests` et `limits`
- [ ] Je sais reconnaître et diagnostiquer un `OOMKilled` et un Pod `Pending`
- [ ] Je connais les trois classes de QoS
- [ ] Je sais expliquer comment fonctionne le HPA et ses prérequis
- [ ] Je sais configurer les probes et les ressources d'une API Spring Boot

**Suite :** [07 - Organisation](../07-organization/README.md) (Namespaces, labels, RBAC)