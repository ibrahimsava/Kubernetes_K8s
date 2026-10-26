

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