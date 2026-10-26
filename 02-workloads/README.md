# 01 - Kubernetes Fundamentals

> **Goal of this module:** understand what Kubernetes is, how a cluster is built, and run your first Pod on a local cluster.

**Estimated time:** 2 to 3 hours · **Level:** beginner (Docker knowledge required)

---

## 1. Why Kubernetes?

With Docker, you can run a container on one machine. In production, this quickly raises questions:

- What happens if the container crashes at 3 AM?
- How do I run 5 copies of my API and spread the traffic between them?
- How do I deploy a new version without downtime?
- How do I run containers across several servers?

**Kubernetes (K8s)** is a container orchestrator. You describe the state you want ("I want 3 copies of this app running"), and Kubernetes works continuously to make reality match that description.

| Problem | What Kubernetes gives you |
|---------|---------------------------|
| Crashes | **Self-healing**: failed containers are restarted or rescheduled |
| Traffic growth | **Scaling**: add or remove replicas manually or automatically |
| New versions | **Rolling updates** and **rollbacks** with no downtime |
| Many services | **Service discovery** and built-in load balancing |
| Config and passwords | **ConfigMaps** and **Secrets** |
| Many servers | **Scheduling**: containers are placed on the best available node |

> **Key idea: declarative model.** You don't tell Kubernetes *how* to do things step by step. You declare the **desired state**, and Kubernetes keeps comparing it with the **actual state** and fixes any difference.

---

## 2. Cluster architecture

A Kubernetes **cluster** is a set of machines split into two roles.

```
┌───────────────────────── CLUSTER ─────────────────────────┐
│                                                           │
│  ┌──────────── CONTROL PLANE (the brain) ─────────────┐   │
│  │  kube-apiserver   etcd   scheduler   controller-mgr│   │
│  └─────────────────────────┬──────────────────────────┘   │
│                            │                              │
│        ┌───────────────────┼───────────────────┐          │
│        ▼                   ▼                   ▼          │
│  ┌──── NODE 1 ───┐  ┌──── NODE 2 ───┐  ┌──── NODE 3 ───┐  │
│  │ kubelet       │  │ kubelet       │  │ kubelet       │  │
│  │ kube-proxy    │  │ kube-proxy    │  │ kube-proxy    │  │
│  │ runtime       │  │ runtime       │  │ runtime       │  │
│  │ [Pod] [Pod]   │  │ [Pod]         │  │ [Pod] [Pod]   │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  │
└───────────────────────────────────────────────────────────┘
```

### Control plane components (the brain)

| Component | Role |
|-----------|------|
| **kube-apiserver** | The front door. Every command (`kubectl`, other components) goes through its REST API. |
| **etcd** | Key-value database storing the whole state of the cluster. |
| **kube-scheduler** | Decides **which node** a new Pod should run on. |
| **kube-controller-manager** | Runs controllers that watch the cluster and fix differences between desired and actual state. |

### Node components (the workers)

| Component | Role |
|-----------|------|
| **kubelet** | Agent on each node. Makes sure the containers described for that node are running and healthy. |
| **kube-proxy** | Handles networking rules so Pods and Services can communicate. |
| **Container runtime** | Actually runs the containers (containerd, CRI-O). Docker images work fine. |

### What happens when you run `kubectl apply`?

1. `kubectl` sends your YAML to the **API server**.
2. The API server validates it and stores it in **etcd**.
3. The **scheduler** notices a Pod with no node and picks one.
4. The **kubelet** on that node pulls the image and starts the container.
5. Controllers keep watching to make sure it stays that way.

---

## 3. Core concepts

### Pod
The **smallest deployable unit** in Kubernetes. A Pod wraps one (sometimes more) containers that share the same network (one IP address) and storage.

- Most Pods contain **one container**.
- Pods are **ephemeral**: if one dies, it is not automatically replaced (unless a controller manages it, see module 02).
- Each Pod gets its own IP, which changes if the Pod is recreated.

### Node
A machine (physical or virtual) in the cluster. With Minikube, your local cluster has a single node that acts as both control plane and worker.

### Namespace
A virtual partition inside a cluster to organize resources (for example `dev`, `staging`, `prod`). Default namespaces:

| Namespace | Purpose |
|-----------|---------|
| `default` | Where your resources go if you don't specify one |
| `kube-system` | Kubernetes system components |
| `kube-public` | Publicly readable data |
| `kube-node-lease` | Node heartbeats |

### Labels
Key-value tags attached to resources (for example `app: nginx`). Kubernetes uses labels to **select and group** resources. They become essential from module 02.

### Manifest (YAML)
A file describing a resource. Every manifest has four main parts:

```yaml
apiVersion: v1          # API version of the resource
kind: Pod               # Type of resource
metadata:               # Name, labels, namespace
  name: nginx-pod
spec:                   # Desired state (the content depends on the kind)
  containers:
    - name: nginx
      image: nginx:1.27
```

### Imperative vs declarative

| Approach | Example | When to use |
|----------|---------|-------------|
| **Imperative** | `kubectl run nginx --image=nginx` | Quick tests and learning |
| **Declarative** | `kubectl apply -f pod.yaml` | Real projects (versioned in Git) |

---

## 4. kubectl basics

`kubectl` is the command-line tool to talk to the API server. The general pattern:

```
kubectl <verb> <resource> [name] [flags]
```

| Command | What it does |
|---------|--------------|
| `kubectl get pods` | List Pods |
| `kubectl get pods -o wide` | List with extra info (node, IP) |
| `kubectl describe pod <name>` | Detailed info and **events** (first stop for debugging) |
| `kubectl logs <name>` | Show container logs |
| `kubectl exec -it <name> -- sh` | Open a shell inside the container |
| `kubectl apply -f <file>` | Create or update from a manifest |
| `kubectl delete pod <name>` | Delete a Pod |
| `kubectl get pod <name> -o yaml` | Show the full YAML stored in the cluster |
| `kubectl explain pod.spec` | Built-in documentation of any field |
| `kubectl api-resources` | List all resource types |

> 💡 `kubectl explain` is a hidden gem: for example `kubectl explain pod.spec.containers` documents every field without leaving the terminal.

---

## 5. Pod lifecycle and common statuses

| Status | Meaning |
|--------|---------|
| `Pending` | Accepted by the cluster, waiting to be scheduled or for the image to be pulled |
| `ContainerCreating` | Image is being pulled, container is being created |
| `Running` | At least one container is running |
| `Succeeded` | All containers finished successfully (jobs) |
| `Failed` | A container ended with an error |
| `CrashLoopBackOff` | The container keeps crashing and Kubernetes keeps restarting it with growing delays |
| `ImagePullBackOff` / `ErrImagePull` | The image cannot be pulled (wrong name, tag or registry access) |

### Debugging checklist

1. `kubectl get pods`: what is the status?
2. `kubectl describe pod <name>`: read the **Events** section at the bottom.
3. `kubectl logs <name>`: what does the application say? (`--previous` for a crashed container)
4. `kubectl exec -it <name> -- sh`: look inside if it is running.

---

## 6. Hands-on: your first cluster and Pod

### Step 1: Start the cluster

```bash
minikube start
```

### Step 2: Verify it works

```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

You should see one node in `Ready` status and the system Pods in `kube-system`.

### Step 3: Run a Pod imperatively

```bash
kubectl run nginx-test --image=nginx:1.27
kubectl get pods
kubectl describe pod nginx-test
```

### Step 4: Run a Pod declaratively

Use the manifest in [`manifests/pod.yaml`](./manifests/pod.yaml):

```bash
kubectl apply -f manifests/pod.yaml
kubectl get pods -o wide
```

### Step 5: Access the Pod

Pods have internal IPs only. For testing, forward a local port to the Pod:

```bash
kubectl port-forward pod/nginx-pod 8080:80
```

Open http://localhost:8080 in your browser. Stop with `Ctrl+C`.

### Step 6: Inspect it from the inside

```bash
kubectl logs nginx-pod
kubectl exec -it nginx-pod -- sh
# inside the container:
ls /usr/share/nginx/html
exit
```

### Step 7: Clean up

```bash
kubectl delete -f manifests/pod.yaml
kubectl delete pod nginx-test
```

> ⚠️ Delete a Pod and it stays deleted. Nothing recreates it. This is exactly the limitation that **Deployments** solve in module 02.

---

## 7. Key takeaways

- Kubernetes keeps the **actual state** equal to the **desired state** you declare.
- The **control plane** decides and stores; the **nodes** run the containers.
- A **Pod** is the smallest unit and is **ephemeral**.
- Prefer **declarative YAML** files versioned in Git.
- When something fails: `get` → `describe` → `logs`.

## ✅ Checklist

- [ok] I can explain what Kubernetes solves compared to plain Docker
- [ok] I can name the control plane and node components and their roles
- [ok] I can write a basic Pod manifest from memory
- [ok] I can start Minikube and run `kubectl get nodes`
- [ok] I can debug a Pod with `describe` and `logs`

**Next:** [02 - Workloads](../02-workloads/README.md) (Deployments, ReplicaSets, rolling updates)









# 02 - Workloads : Deployments, ReplicaSets et mises à jour

> **Objectif du module :** faire tourner une application de façon fiable avec plusieurs copies, la mettre à l'échelle, la mettre à jour sans interruption et revenir en arrière en cas de problème.

**Durée estimée :** 3 à 4 heures · **Prérequis :** module 01 terminé, cluster Minikube démarré

---

## 1. Le problème du module 01

Au module 01, tu as vu qu'un Pod supprimé **ne revient pas**. En production, ce n'est pas acceptable :

- Si le Pod plante ou si le nœud tombe, l'application disparaît.
- Tu ne peux pas avoir plusieurs copies d'un Pod avec un seul manifest.
- Tu ne peux pas mettre à jour l'image sans supprimer et recréer le Pod à la main.

On ne crée donc presque **jamais de Pods directement**. On utilise un **contrôleur** qui gère les Pods à notre place.

---

## 2. ReplicaSet

Un **ReplicaSet** garantit qu'un **nombre précis de Pods identiques** tourne en permanence.

```
ReplicaSet (replicas: 3)
 ├── Pod 1
 ├── Pod 2
 └── Pod 3   ← si l'un meurt, le ReplicaSet en recrée un
```

Le ReplicaSet fonctionne ainsi :

1. Il cherche tous les Pods qui correspondent à son **selector** (des labels).
2. Il compte combien il en trouve.
3. S'il y en a **moins** que souhaité, il en crée. S'il y en a **plus**, il en supprime.

C'est la **boucle de réconciliation** vue au module 01 : état souhaité contre état réel.

> En pratique, tu ne crées presque jamais de ReplicaSet toi-même. Tu crées un **Deployment**, qui crée et gère les ReplicaSets pour toi.

---

## 3. Deployment

Un **Deployment** est la ressource standard pour faire tourner une application **sans état** (une API, un frontend...). Il ajoute au ReplicaSet :

| Fonction | Description |
|----------|-------------|
| **Mises à jour progressives** | Remplace les Pods ancienne version par la nouvelle version, petit à petit |
| **Rollback** | Revient à une version précédente en une commande |
| **Historique** | Conserve les révisions précédentes |
| **Scaling** | Change le nombre de réplicas d'un seul changement |

### La hiérarchie

```
Deployment  →  ReplicaSet  →  Pods
   web           web-7d9f8c      web-7d9f8c-abcde
                                 web-7d9f8c-fghij
                                 web-7d9f8c-klmno
```

Les noms sont générés automatiquement : `<deployment>-<hash du template>-<suffixe aléatoire>`. Quand tu changes l'image, un **nouveau ReplicaSet** est créé avec un autre hash, et l'ancien est conservé (à 0 Pod) pour permettre le rollback.

---

## 4. Anatomie d'un manifest Deployment

Fichier [`manifests/deployment.yaml`](./manifests/deployment.yaml) :

```yaml
apiVersion: apps/v1            # attention : apps/v1, pas v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
spec:
  replicas: 3                  # nombre de Pods souhaité
  selector:
    matchLabels:
      app: web                 # quels Pods ce Deployment gère-t-il ?
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1              # 1 Pod en plus autorisé pendant la mise à jour
      maxUnavailable: 0        # 0 Pod indisponible autorisé
  template:                    # le modèle des Pods à créer
    metadata:
      labels:
        app: web               # DOIT correspondre au selector
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
```

### Les trois blocs à bien comprendre

| Bloc | Rôle |
|------|------|
| `replicas` | Combien de Pods tu veux |
| `selector.matchLabels` | Comment le Deployment **retrouve** ses Pods |
| `template` | Le **modèle** de Pod (c'est un manifest de Pod sans `apiVersion` ni `kind`) |

> ⚠️ **Règle d'or :** les labels du `template.metadata.labels` doivent **correspondre** au `selector.matchLabels`, sinon Kubernetes refuse le manifest. Le `selector` ne peut plus être modifié après la création.

---

## 5. Mises à jour progressives (Rolling Update)

Quand tu modifies le **template** (par exemple l'image), Kubernetes remplace les Pods **un par un** pour que l'application reste disponible.

```
Avant :   [v1] [v1] [v1]
Étape 1 : [v1] [v1] [v1] [v2]      ← un nouveau Pod démarre (maxSurge)
Étape 2 : [v1] [v1] [v2]           ← un ancien Pod est supprimé
Étape 3 : [v1] [v1] [v2] [v2]
Étape 4 : [v1] [v2] [v2]
...
Après :   [v2] [v2] [v2]
```

### Les deux paramètres de contrôle

| Paramètre | Signification | Valeur par défaut |
|-----------|---------------|-------------------|
| `maxSurge` | Combien de Pods **en plus** du nombre souhaité pendant la mise à jour | 25 % |
| `maxUnavailable` | Combien de Pods peuvent être **indisponibles** pendant la mise à jour | 25 % |

Avec `maxSurge: 1` et `maxUnavailable: 0`, Kubernetes ne supprime jamais un ancien Pod avant que le nouveau soit **prêt**. C'est la configuration la plus sûre : zéro interruption.

### Ce qui déclenche (ou non) une mise à jour

| Modification | Déclenche un rollout ? |
|--------------|------------------------|
| Image du conteneur | ✅ Oui |
| Variables d'environnement, ports, ressources (dans `template`) | ✅ Oui |
| Nombre de `replicas` | ❌ Non, c'est juste du scaling |

### Autre stratégie : Recreate

```yaml
strategy:
  type: Recreate
```

Supprime **tous** les anciens Pods puis crée les nouveaux. Il y a une interruption, mais on l'utilise quand deux versions ne peuvent pas tourner en même temps (par exemple une migration de base de données incompatible).

---

## 6. Rollback

Chaque modification du template crée une **révision**. En cas de problème, tu reviens à la précédente :

```bash
kubectl rollout history deployment/web          # voir les révisions
kubectl rollout undo deployment/web             # revenir à la précédente
kubectl rollout undo deployment/web --to-revision=1
```

> 💡 Un `undo` crée lui-même une **nouvelle révision** (qui reprend le contenu de l'ancienne). L'historique ne perd rien.

Pour que l'historique soit lisible, annote chaque changement :

```bash
kubectl annotate deployment/web kubernetes.io/change-cause="passage a nginx 1.27-alpine"
```

### Que se passe-t-il si la nouvelle version est cassée ?

Avec `maxUnavailable: 0`, si les nouveaux Pods ne démarrent pas (mauvaise image par exemple), Kubernetes **garde les anciens Pods en vie** et bloque la mise à jour. Ton application continue de fonctionner. Tu vois les nouveaux Pods en `ImagePullBackOff` ou `CrashLoopBackOff`, et tu fais un `rollout undo`.

---

## 7. Scaling

```bash
kubectl scale deployment web --replicas=5     # impératif
```

ou modifie `replicas: 5` dans le YAML puis `kubectl apply -f`. L'approche déclarative reste préférable : le fichier dans Git reflète l'état réel.

> Le scaling **automatique** (HPA) est vu au module 06.

---

## 8. Les autres types de workloads

Le Deployment couvre la majorité des cas, mais il en existe d'autres :

| Ressource | Usage | Exemple |
|-----------|-------|---------|
| **Deployment** | Application sans état, interchangeable | API Spring Boot, frontend Angular |
| **StatefulSet** | Application **avec état**, identité stable et stockage persistant | PostgreSQL (module 05) |
| **DaemonSet** | Un Pod **par nœud** | Agent de logs, monitoring |
| **Job** | Tâche qui s'exécute **une fois** jusqu'à réussite | Migration, import de données |
| **CronJob** | Job **planifié** | Sauvegarde nocturne |

---

## 9. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl create deployment web --image=nginx:1.27 --replicas=3` | Crée un Deployment (impératif) |
| `kubectl create deployment web --image=nginx:1.27 --dry-run=client -o yaml` | Génère le YAML sans rien créer, pratique pour démarrer un manifest |
| `kubectl get deployments` | Liste les Deployments |
| `kubectl get rs` | Liste les ReplicaSets |
| `kubectl get pods -l app=web` | Filtre les Pods par label |
| `kubectl get pods -w` | Suit les changements en direct |
| `kubectl scale deployment web --replicas=5` | Change le nombre de réplicas |
| `kubectl set image deployment/web nginx=nginx:1.27-alpine` | Change l'image |
| `kubectl rollout status deployment/web` | Suit une mise à jour en cours |
| `kubectl rollout history deployment/web` | Affiche les révisions |
| `kubectl rollout undo deployment/web` | Revient en arrière |
| `kubectl rollout restart deployment/web` | Redémarre tous les Pods progressivement |
| `kubectl describe deployment web` | Détails et événements |

---

## 10. Pratique : de l'application à la mise à jour

> 💡 **Avec ta connexion lente :** les images sont téléchargées par Minikube la première fois. Pour la mise à jour, on utilise `nginx:1.27-alpine` (environ 20 Mo), beaucoup plus légère que `nginx:1.27`. Les Pods peuvent rester en `ContainerCreating` quelques minutes la première fois, c'est normal.

### Étape 1 : Créer le Deployment

```bash
kubectl apply -f manifests/deployment.yaml
kubectl get deployments
kubectl get rs
kubectl get pods -o wide
```

Tu dois voir **3 Pods** `web-xxxxx-yyyyy` en `Running`, **1 ReplicaSet** et **1 Deployment** `3/3`.

### Étape 2 : Observer l'auto-réparation

Dans un terminal, suis les Pods :

```bash
kubectl get pods -w
```

Dans un **deuxième terminal**, supprime un Pod :

```bash
kubectl delete pod <nom-d-un-pod-web>
```

Le ReplicaSet en recrée un **immédiatement**. Compare avec le module 01 : c'est exactement ce qui manquait.

### Étape 3 : Mettre à l'échelle

```bash
kubectl scale deployment web --replicas=5
kubectl get pods
kubectl scale deployment web --replicas=2
kubectl get pods
```

### Étape 4 : Accéder à l'application

```bash
kubectl port-forward deployment/web 8080:80
```

Ouvre http://localhost:8080. Attention : `port-forward` se connecte à **un seul Pod**. Pour répartir le trafic entre tous les Pods, il faut un **Service** (module 03).

### Étape 5 : Faire une mise à jour progressive

Remets 3 réplicas, puis dans un terminal suis les Pods (`kubectl get pods -w`) et dans l'autre :

```bash
kubectl scale deployment web --replicas=3
kubectl set image deployment/web nginx=nginx:1.27-alpine
kubectl annotate deployment/web kubernetes.io/change-cause="passage a nginx 1.27-alpine"
kubectl rollout status deployment/web
```

Observe : de nouveaux Pods apparaissent, les anciens sont supprimés **un par un**. Vérifie ensuite :

```bash
kubectl get rs
kubectl rollout history deployment/web
kubectl exec deploy/web -- nginx -v
```

Tu dois voir **deux ReplicaSets** : l'ancien à 0 Pod, le nouveau à 3.

### Étape 6 : Provoquer une mise à jour cassée, puis revenir en arrière

```bash
kubectl set image deployment/web nginx=nginx:cette-version-nexiste-pas
kubectl rollout status deployment/web
```

Dans un autre terminal :

```bash
kubectl get pods
```

Tu verras des nouveaux Pods en `ErrImagePull` / `ImagePullBackOff`, **mais les anciens Pods tournent toujours** : l'application n'est pas interrompue. Fais `Ctrl+C` sur le `rollout status`, puis :

```bash
kubectl rollout undo deployment/web
kubectl rollout status deployment/web
kubectl get pods
```

### Étape 7 : Nettoyer

```bash
kubectl delete -f manifests/deployment.yaml
```

Cela supprime le Deployment, son ReplicaSet et tous ses Pods.

---

## 11. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `selector does not match template labels` | Labels du `template` différents du `selector` | Aligne les deux |
| Pods en `Pending` | Pas assez de ressources sur le nœud | `kubectl describe pod`, regarde les Events |
| Pods en `ImagePullBackOff` | Mauvais nom ou tag d'image | Corrige l'image ou fais `rollout undo` |
| `rollout status` reste bloqué | Les nouveaux Pods ne deviennent jamais prêts | `kubectl get pods`, `describe`, `logs` puis `rollout undo` |
| `field is immutable` | Tu as modifié le `selector` d'un Deployment existant | Supprime et recrée le Deployment |
| `kubectl apply` ne fait rien | Aucun changement dans le `template` | Normal, c'est le comportement attendu |

---

## 12. Points clés à retenir

- On ne crée **pas** de Pods seuls : on utilise un **Deployment**.
- **Deployment → ReplicaSet → Pods** : le Deployment gère les mises à jour, le ReplicaSet maintient le nombre de Pods.
- Les `labels` et le `selector` relient les ressources entre elles.
- Un changement du **template** déclenche un rollout. Le simple changement de `replicas` ne le fait pas.
- `maxSurge` et `maxUnavailable` contrôlent la vitesse et la sécurité d'une mise à jour.
- `rollout undo` te ramène à la version précédente en quelques secondes.
- Les Pods ont des noms et des IP **temporaires** : il faut un **Service** pour les atteindre de façon stable (module 03).

## ✅ Checklist

- [ ] Je sais expliquer la différence entre Pod, ReplicaSet et Deployment
- [ ] Je sais écrire un manifest Deployment avec `selector` et `template`
- [ ] Je sais mettre à l'échelle un Deployment
- [ ] Je sais faire une mise à jour progressive et suivre son avancement
- [ ] Je sais faire un rollback et lire l'historique des révisions
- [ ] Je sais expliquer ce que font `maxSurge` et `maxUnavailable`

**Suite :** [03 - Networking](../03-networking/README.md) (Services, Ingress, DNS)