# 07 - Organisation : Namespaces, labels et RBAC

> **Objectif du module :** organiser un cluster partagé entre plusieurs applications et environnements, limiter ce que chacun peut consommer, et contrôler qui a le droit de faire quoi.

**Durée estimée :** 4 heures · **Prérequis :** modules 01 à 06 terminés, cluster Minikube démarré

---

## 1. Le problème

Jusqu'ici, tout ce que tu as créé vit dans le namespace `default`. Dans un vrai cluster, on a besoin de :

- **séparer** les environnements (dev, test, production) et les équipes
- **retrouver** et regrouper des ressources (« toutes les ressources de la boutique »)
- **plafonner** ce qu'un environnement peut consommer
- **contrôler** qui peut lire, modifier ou supprimer quoi

| Besoin | Outil |
|--------|-------|
| Séparer | **Namespaces** |
| Regrouper et retrouver | **Labels, selectors et annotations** |
| Plafonner | **ResourceQuota** et **LimitRange** |
| Contrôler les droits | **RBAC** |

---

## 2. Namespaces

Un **namespace** est une partition **logique** d'un cluster. Chaque namespace a ses propres ressources, et les noms n'y doivent être uniques que **dans le namespace**.

```
Cluster
 ├── namespace dev     →  web, api, postgres...
 ├── namespace test    →  web, api, postgres...   (mêmes noms, aucun conflit)
 └── namespace prod    →  web, api, postgres...
```

### Namespaces existants par défaut

| Namespace | Contenu |
|-----------|---------|
| `default` | Ce que tu crées si tu n'en précises pas |
| `kube-system` | Composants du système (API server, CoreDNS...) |
| `kube-public` | Données lisibles par tous |
| `kube-node-lease` | Signaux de vie des nœuds |

### Créer et utiliser un namespace

```bash
kubectl create namespace dev                       # impératif
kubectl apply -f namespaces.yaml                   # déclaratif (recommandé)
kubectl get pods -n dev                            # un namespace précis
kubectl get pods -A                                # tous les namespaces
kubectl apply -f app.yaml -n dev                   # créer dans dev
```

Tu peux aussi fixer le namespace **dans le manifest** :

```yaml
metadata:
  name: web
  namespace: dev
```

### Changer de namespace par défaut

Pour éviter de taper `-n dev` à chaque commande :

```bash
kubectl config set-context --current --namespace=dev
kubectl config view --minify | findstr namespace      # PowerShell : vérifier
```

⚠️ **Pense à revenir** à `default` après, sinon tu risques d'appliquer des commandes au mauvais endroit :

```bash
kubectl config set-context --current --namespace=default
```

### DNS entre namespaces

Comme vu au module 03 :

| Depuis | Pour joindre le Service `web` de `dev` |
|--------|---------------------------------------|
| Le namespace `dev` | `web` |
| Un autre namespace | `web.dev` ou `web.dev.svc.cluster.local` |

### Ressources avec ou sans namespace

Toutes les ressources ne sont pas rattachées à un namespace :

| Avec namespace | Sans namespace (cluster-wide) |
|----------------|-------------------------------|
| Pods, Deployments, Services, ConfigMaps, Secrets, PVC, Ingress | **Nodes**, **PersistentVolumes**, **StorageClasses**, **Namespaces**, ClusterRoles |

```bash
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

### Ce qu'il faut savoir

- **Supprimer un namespace supprime tout ce qu'il contient** : Pods, Services, Secrets, volumes... C'est irréversible.
- Un namespace n'est **pas une frontière de sécurité à lui seul** : par défaut, les Pods de tous les namespaces peuvent se parler. Il faut y ajouter RBAC, quotas et NetworkPolicies.
- Pour séparer **fortement** la production du reste, on utilise souvent **des clusters distincts**.

---

## 3. Labels, selectors et annotations

### Labels

Un **label** est une paire clé-valeur attachée à une ressource, pour l'**identifier et la regrouper**.

```yaml
metadata:
  labels:
    app: web
    env: dev
    tier: frontend
```

Tu en as déjà utilisé : le `selector` d'un Deployment ou d'un Service retrouve ses Pods grâce aux labels.

### Labels recommandés par Kubernetes

Pour que les outils (dashboards, Helm...) comprennent tes ressources, on utilise des labels standards :

| Label | Signification | Exemple |
|-------|---------------|---------|
| `app.kubernetes.io/name` | Nom de l'application | `web` |
| `app.kubernetes.io/instance` | Instance précise | `web-dev` |
| `app.kubernetes.io/version` | Version | `1.27` |
| `app.kubernetes.io/component` | Rôle dans l'architecture | `frontend` |
| `app.kubernetes.io/part-of` | Application globale | `boutique` |

### Filtrer avec des selectors

```bash
kubectl get pods --show-labels
kubectl get pods -l app=web                          # égalité
kubectl get pods -l app=web,tier=frontend            # ET logique
kubectl get pods -l 'env in (dev,test)'              # appartenance à un ensemble
kubectl get pods -l 'tier notin (backend)'
kubectl get pods -l '!canary'                        # label absent
kubectl get pods -A -l app.kubernetes.io/part-of=boutique
```

### Modifier des labels

```bash
kubectl label pod web-abc env=dev                    # ajouter
kubectl label pod web-abc env=test --overwrite       # modifier
kubectl label pod web-abc env-                       # supprimer (le tiret final)
```

### Annotations

Une **annotation** est aussi une paire clé-valeur, mais **non identifiante** : on ne sélectionne **pas** avec. Elle sert à stocker des informations pour les humains et les outils.

```yaml
metadata:
  annotations:
    description: "Frontend de la boutique"
    contact: "equipe-web@exemple.com"
    kubernetes.io/change-cause: "passage a nginx 1.27"
```

| | Labels | Annotations |
|---|--------|-------------|
| Sélectionnables | ✅ Oui | ❌ Non |
| Contenu | Court, structuré | Peut être long, libre |
| Usage | Regroupement, ciblage | Documentation, configuration d'outils |

---

## 4. ResourceQuota et LimitRange

Dans un cluster partagé, une équipe ne doit pas pouvoir tout consommer. Deux ressources, appliquées **par namespace**, s'en chargent.

### ResourceQuota : un plafond global

Fichier [`manifests/quota.yaml`](./manifests/quota.yaml) :

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota-dev
  namespace: dev
spec:
  hard:
    pods: "4"
    requests.cpu: "500m"
    requests.memory: 512Mi
    limits.cpu: "1"
    limits.memory: 1Gi
```

Quand le plafond est atteint, Kubernetes **refuse** de créer de nouvelles ressources qui le dépasseraient. Tu peux aussi limiter le nombre de Services, de PVC, de ConfigMaps...

### LimitRange : des valeurs par défaut et des bornes

Fichier [`manifests/limitrange.yaml`](./manifests/limitrange.yaml) :

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: limites-par-defaut
  namespace: dev
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 50m
        memory: 64Mi
      default:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: "1"
        memory: 512Mi
```

| Champ | Effet |
|-------|-------|
| `defaultRequest` | `requests` appliquées si le conteneur n'en déclare pas |
| `default` | `limits` appliquées si le conteneur n'en déclare pas |
| `max` / `min` | Bornes : un conteneur hors bornes est refusé |

### Pourquoi les deux vont ensemble

Si un ResourceQuota impose des `requests` et `limits` de CPU et de mémoire, **tout Pod qui n'en déclare pas est refusé**. Le **LimitRange** lui donne alors des valeurs par défaut, et le Pod est accepté. Ça rejoint le module 06 : les `requests` sont ce que le quota additionne.

---

## 5. RBAC : qui peut faire quoi

**RBAC** (Role-Based Access Control) décide quelles actions chaque identité peut effectuer sur quelles ressources. Chaque requête à l'API server passe par deux étapes :

```
Requête  →  Authentification (qui es-tu ?)  →  Autorisation / RBAC (as-tu le droit ?)  →  Exécution
```

### Les identités (subjects)

| Type | Description |
|------|-------------|
| **User** | Une personne. Kubernetes ne gère **pas** de comptes utilisateurs : l'identité vient d'un certificat, d'un fournisseur OIDC (Google, Azure AD...) ou du cloud |
| **Group** | Un groupe d'utilisateurs |
| **ServiceAccount** | Une identité pour un **programme** (un Pod, un pipeline CI/CD). C'est la seule gérée par Kubernetes |

### Les quatre objets

| Objet | Portée | Rôle |
|-------|--------|------|
| **Role** | Un namespace | Liste de **permissions** |
| **ClusterRole** | Tout le cluster | Liste de permissions (ressources cluster-wide ou réutilisable partout) |
| **RoleBinding** | Un namespace | **Attache** un Role (ou ClusterRole) à une identité, **dans ce namespace** |
| **ClusterRoleBinding** | Tout le cluster | Attache un ClusterRole à une identité, **partout** |

```
Identité  ◄──RoleBinding──►  Role  ──►  permissions
```

### Écrire un Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: lecteur-pods
  namespace: dev
rules:
  - apiGroups: [""]                          # "" = groupe de base (core)
    resources: ["pods", "pods/log", "services"]
    verbs: ["get", "list", "watch"]          # lecture seule
```

| Champ | Signification |
|-------|---------------|
| `apiGroups` | Groupe de l'API : `""` (Pods, Services, ConfigMaps, Secrets), `apps` (Deployments), `batch` (Jobs)... |
| `resources` | Types de ressources |
| `verbs` | Actions : `get`, `list`, `watch`, `create`, `update`, `patch`, `delete` |

⚠️ Les permissions sont **additives** : il n'existe pas de « refus » en RBAC. Ce qui n'est pas explicitement autorisé est interdit.

### Attacher le Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lecteur-binding
  namespace: dev
subjects:
  - kind: ServiceAccount
    name: lecteur
    namespace: dev
roleRef:
  kind: Role
  name: lecteur-pods
  apiGroup: rbac.authorization.k8s.io
```

### ClusterRoles prédéfinis

Kubernetes en fournit quatre, utiles dans un `RoleBinding` pour limiter les droits à **un namespace** :

| ClusterRole | Droits |
|-------------|--------|
| `view` | Lecture seule de la plupart des ressources (**sans** les Secrets) |
| `edit` | Lecture et écriture de la plupart des ressources (Secrets compris) |
| `admin` | `edit` + gestion des rôles dans le namespace |
| `cluster-admin` | **Tout**, partout |

Un `RoleBinding` qui référence le ClusterRole `view` donne la lecture **seulement dans son namespace**, pas dans tout le cluster. C'est la pratique la plus courante.

### Le principe du moindre privilège

Donne à chaque identité **le strict nécessaire** :

| ❌ À éviter | ✅ À faire |
|-------------|-----------|
| Donner `cluster-admin` à un pipeline CI/CD | Un ServiceAccount dédié avec un Role limité à un namespace |
| `verbs: ["*"]` et `resources: ["*"]` | Lister précisément les verbes et ressources |
| Donner l'accès aux Secrets « au cas où » | Aucun accès aux Secrets, sauf nécessité |
| Utiliser le ServiceAccount `default` pour tout | Un ServiceAccount par application |

Un exemple destiné à ton futur pipeline (module 09) est dans [`manifests/rbac-deployer.yaml`](./manifests/rbac-deployer.yaml).

### Vérifier les droits : `kubectl auth can-i`

```bash
kubectl auth can-i delete pods -n dev                                  # moi
kubectl auth can-i list pods -n dev --as=system:serviceaccount:dev:lecteur
kubectl auth can-i --list -n dev --as=system:serviceaccount:dev:lecteur
```

Le format d'identité d'un ServiceAccount est `system:serviceaccount:<namespace>:<nom>`. L'option `--as` (impersonation) te permet de tester les droits d'une identité sans te connecter avec.

---

## 6. Contextes et kubeconfig

Ton fichier `~/.kube/config` (sous Windows : `C:\Users\Ibrahim\.kube\config`) stocke les clusters auxquels tu peux te connecter, avec leurs identités. Un **contexte** associe un cluster, un utilisateur et un namespace par défaut.

```bash
kubectl config get-contexts                  # lister les contextes
kubectl config current-context               # contexte actif
kubectl config use-context minikube          # changer de cluster
kubectl config set-context --current --namespace=dev
```

⚠️ Avant toute commande destructive, **vérifie ton contexte et ton namespace**. Supprimer des ressources dans le mauvais cluster est une erreur classique en production.

---

## 7. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl get ns --show-labels` | Liste les namespaces |
| `kubectl get all -n dev` | Principales ressources d'un namespace |
| `kubectl get pods -A` | Pods de tous les namespaces |
| `kubectl config set-context --current --namespace=<ns>` | Change le namespace par défaut |
| `kubectl label <ressource> <nom> cle=valeur` | Ajoute un label |
| `kubectl get pods -l 'env in (dev,test)'` | Filtre par selector |
| `kubectl describe quota -n dev` | Utilisation d'un quota |
| `kubectl describe limitrange -n dev` | Valeurs par défaut d'un namespace |
| `kubectl get role,rolebinding -n dev` | Rôles et attachements |
| `kubectl auth can-i <verbe> <ressource> -n <ns> --as=<identité>` | Teste un droit |
| `kubectl delete namespace <ns>` | ⚠️ Supprime le namespace et tout son contenu |

---

## 8. Pratique

> Toutes les images utilisées (`nginx:1.27`, `busybox:1.36`) sont déjà chez toi : pas de téléchargement lourd dans ce module.
>
> ℹ️ Sur Minikube, tu es **administrateur du cluster**, ce qui te permet de tester les droits d'autres identités avec `--as`.

Commandes pour **PowerShell**, depuis le dossier du module.

### Étape 1 : Créer deux namespaces

```powershell
kubectl apply -f manifests/namespaces.yaml
kubectl get ns --show-labels
```

### Étape 2 : Le même nom dans deux namespaces

```powershell
kubectl apply -f manifests/app.yaml -n dev
kubectl apply -f manifests/app.yaml -n test
kubectl get pods -A -l app=web
kubectl get deployments -A
```

Deux Deployments nommés `web` coexistent sans conflit.

### Étape 3 : DNS entre namespaces

```powershell
kubectl run tmp -n test --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web
kubectl run tmp -n test --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web.dev
```

Les deux marchent depuis `test` : la première atteint le `web` de **test**, la seconde celui de **dev**.

### Étape 4 : Changer de namespace par défaut

```powershell
kubectl config set-context --current --namespace=dev
kubectl get pods
kubectl config set-context --current --namespace=default
kubectl get pods
```

Sans `-n`, tu vois les Pods de `dev`, puis ceux de `default` (probablement aucun).

### Étape 5 : Labels et selectors

```powershell
kubectl get pods -n dev --show-labels
kubectl label pods -l app=web env=dev -n dev
kubectl label pods -l app=web env=test -n test
kubectl get pods -A -l env=dev
kubectl get pods -A -l 'env in (dev,test)'
kubectl get pods -A -l 'env notin (dev)'
kubectl get pods -A -l app.kubernetes.io/part-of=boutique
```

### Étape 6 : LimitRange et ResourceQuota

```powershell
kubectl apply -f manifests/limitrange.yaml
kubectl apply -f manifests/quota.yaml
kubectl rollout restart deployment/web -n dev
kubectl rollout status deployment/web -n dev
kubectl describe pod -n dev -l app=web
```

Dans `describe`, les nouveaux Pods portent désormais des `Requests` et `Limits` : c'est le **LimitRange** qui les a ajoutés automatiquement. Puis :

```powershell
kubectl describe quota quota-dev -n dev
kubectl scale deployment web --replicas=6 -n dev
kubectl get pods -n dev
kubectl describe rs -n dev
```

Le plafond est de **4 Pods** : tu n'en obtiens que 4. Dans `describe rs`, cherche `exceeded quota`.

```powershell
kubectl scale deployment web --replicas=2 -n dev
```

### Étape 7 : RBAC

```powershell
kubectl apply -f manifests/rbac.yaml
kubectl get sa,role,rolebinding -n dev
kubectl get sa,rolebinding -n test
```

Teste les droits du ServiceAccount `lecteur` (namespace `dev`) :

```powershell
kubectl auth can-i list pods -n dev --as=system:serviceaccount:dev:lecteur
kubectl auth can-i delete pods -n dev --as=system:serviceaccount:dev:lecteur
kubectl auth can-i list pods -n test --as=system:serviceaccount:dev:lecteur
kubectl auth can-i list secrets -n dev --as=system:serviceaccount:dev:lecteur
kubectl auth can-i --list -n dev --as=system:serviceaccount:dev:lecteur
```

Résultats attendus : `yes`, `no`, `no`, `no`. Et pour `observateur` (namespace `test`, ClusterRole `view`) :

```powershell
kubectl auth can-i get deployments -n test --as=system:serviceaccount:test:observateur
kubectl auth can-i delete deployments -n test --as=system:serviceaccount:test:observateur
kubectl auth can-i get secrets -n test --as=system:serviceaccount:test:observateur
kubectl auth can-i get pods -n dev --as=system:serviceaccount:test:observateur
```

Résultats attendus : `yes`, `no`, `no`, `no`. Essaie une vraie commande avec cette identité :

```powershell
kubectl get pods -n dev --as=system:serviceaccount:dev:lecteur
kubectl delete pod -n dev -l app=web --as=system:serviceaccount:dev:lecteur
```

La seconde échoue avec `forbidden`.

### Étape 8 : Nettoyer

```powershell
kubectl delete namespace dev test
kubectl config set-context --current --namespace=default
kubectl get ns
```

La suppression d'un namespace supprime **tout** : Deployments, Services, quota, RBAC. Cela peut prendre une minute.

---

## 9. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `Error from server (Forbidden)` | Il manque une permission RBAC | `kubectl auth can-i`, puis ajoute le verbe au Role |
| `forbidden: exceeded quota` | Plafond du namespace atteint | `kubectl describe quota`, libère ou augmente le quota |
| `must specify limits.cpu` / `requests.memory` | Un quota impose des ressources et le Pod n'en déclare pas | Ajoute des `resources` ou un **LimitRange** avec des défauts |
| Ressource introuvable alors qu'elle existe | Tu regardes le mauvais namespace | `kubectl get <type> -A`, ou ajoute `-n` |
| Mauvais namespace par défaut | Un `set-context` oublié | `kubectl config view --minify`, remets `default` |
| `namespace ... is being terminated` | Suppression en cours, avec des ressources lentes à partir | Attends ; vérifie avec `kubectl get all -n <ns>` |
| Service injoignable depuis un autre namespace | Nom court utilisé hors du namespace | Utilise `web.dev` |
| RoleBinding sans effet | Mauvais namespace dans `subjects`, ou nom du Role incorrect | Vérifie `kubectl describe rolebinding` |
| `ClusterRoleBinding` trop large | Droits donnés sur tout le cluster | Préfère un `RoleBinding` limité au namespace |

---

## 10. Points clés à retenir

- Un **namespace** sépare logiquement les ressources, mais ne protège pas à lui seul : il faut y ajouter **RBAC**, **quotas** et **NetworkPolicies**.
- Supprimer un namespace **supprime tout** ce qu'il contient.
- Les **labels** identifient et regroupent (sélectionnables), les **annotations** documentent (non sélectionnables).
- **ResourceQuota** plafonne un namespace. **LimitRange** donne des valeurs par défaut et des bornes aux conteneurs.
- **RBAC** = identité + Role + binding. Les permissions sont **additives** : rien n'est autorisé par défaut.
- Un **RoleBinding** limite les droits à un namespace, même quand il référence un ClusterRole.
- **Moindre privilège** : un ServiceAccount dédié par application ou pipeline, jamais `cluster-admin` par commodité.
- Vérifie toujours ton **contexte** et ton **namespace** avant une commande destructive.

## ✅ Checklist

- [ ] Je sais expliquer à quoi servent les namespaces et leurs limites de sécurité
- [ ] Je sais créer, cibler et supprimer un namespace, et je connais les risques
- [ ] Je sais utiliser des labels et des selectors (égalité et ensembles)
- [ ] Je sais la différence entre labels et annotations
- [ ] Je sais configurer un ResourceQuota et un LimitRange
- [ ] Je sais écrire un Role, un RoleBinding et un ServiceAccount
- [ ] Je sais tester les droits d'une identité avec `kubectl auth can-i --as`
- [ ] Je sais expliquer le principe du moindre privilège

**Suite :** [08 - Helm et Kustomize](../08-helm-kustomize/README.md) (packaging et environnements)