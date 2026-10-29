# 05 - Stockage : Volumes, PV/PVC et PostgreSQL avec StatefulSet

> **Objectif du module :** conserver des données au-delà de la vie d'un Pod, et faire tourner une base de données PostgreSQL de façon fiable dans Kubernetes.

**Durée estimée :** 4 heures · **Prérequis :** modules 01 à 04 terminés, cluster Minikube démarré

---

## 1. Le problème

Le système de fichiers d'un conteneur est **éphémère** : quand le conteneur est recréé, tout ce qu'il avait écrit disparaît. Pour une API sans état (module 02), ce n'est pas grave. Pour une **base de données**, c'est une catastrophe.

```
Pod PostgreSQL ──écrit──► fichiers de la base
      │
   (le Pod meurt)
      ▼
Nouveau Pod ──► base VIDE ❌
```

Il faut un stockage qui **survit** au Pod. Kubernetes propose pour cela les **volumes**.

---

## 2. Les volumes

Un **volume** est un dossier monté dans un conteneur. Selon son type, sa durée de vie change :

| Type | Durée de vie | Usage |
|------|--------------|-------|
| **emptyDir** | La vie du **Pod** (survit à un redémarrage de conteneur, pas à la suppression du Pod) | Partager des fichiers entre conteneurs d'un même Pod, cache temporaire |
| **hostPath** | Celle du **nœud** | Tests uniquement : dangereux en production (dépend d'une machine précise) |
| **configMap / secret** | Celle de l'objet | Configuration (module 04) |
| **persistentVolumeClaim** | **Indépendante du Pod** | Données qui doivent survivre : bases de données, fichiers uploadés |

### emptyDir

```yaml
volumes:
  - name: shared
    emptyDir: {}
```

Le dossier est créé vide quand le Pod démarre et supprimé avec lui. Les **conteneurs du même Pod** peuvent le partager (voir [`manifests/emptydir-pod.yaml`](./manifests/emptydir-pod.yaml)).

---

## 3. PersistentVolume, PersistentVolumeClaim et StorageClass

Pour un stockage durable, Kubernetes sépare **qui fournit** le stockage de **qui l'utilise** :

| Ressource | Rôle | Analogie |
|-----------|------|----------|
| **PersistentVolume (PV)** | Un morceau de stockage réel dans le cluster | Un disque disponible |
| **PersistentVolumeClaim (PVC)** | Une **demande** de stockage par une application | « Je voudrais 1 Go » |
| **StorageClass** | Une « recette » pour **créer** des PV automatiquement | Un catalogue de types de disques |

```
Pod ──utilise──► PVC ──lié à──► PV ──► disque réel
 (je veux 1 Gi)   (demande)    (fourni)
```

### Le déroulement (provisionnement dynamique)

1. Tu crées un **PVC** qui demande 1 Gi.
2. La **StorageClass** par défaut crée automatiquement un **PV** correspondant.
3. Le PVC passe à l'état **Bound** (lié au PV).
4. Le Pod monte le PVC comme volume.

Sur **Minikube**, une StorageClass nommée `standard` est déjà installée : tu n'as rien à configurer.

```bash
kubectl get storageclass
```

### Manifest d'un PVC

Fichier [`manifests/pvc.yaml`](./manifests/pvc.yaml) :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Et dans un Pod :

```yaml
containers:
  - name: app
    volumeMounts:
      - name: stockage
        mountPath: /data
volumes:
  - name: stockage
    persistentVolumeClaim:
      claimName: demo-pvc
```

### Modes d'accès

| Mode | Abréviation | Signification |
|------|-------------|---------------|
| `ReadWriteOnce` | RWO | Lecture/écriture par **un seul nœud** à la fois. Le plus courant pour une base de données. |
| `ReadOnlyMany` | ROX | Lecture seule par **plusieurs nœuds** |
| `ReadWriteMany` | RWX | Lecture/écriture par **plusieurs nœuds** (nécessite un stockage réseau, par exemple NFS) |
| `ReadWriteOncePod` | RWOP | Lecture/écriture par **un seul Pod** |

### Politique de récupération (reclaimPolicy)

Que devient le PV quand le PVC est supprimé ?

| Politique | Effet |
|-----------|-------|
| `Delete` | Le PV **et les données** sont supprimés (défaut avec Minikube et la plupart des clouds) |
| `Retain` | Le PV est conservé avec ses données, pour récupération manuelle |

> ⚠️ **Supprimer un PVC supprime en général les données.** C'est irréversible.

### États d'un PVC

| État | Signification |
|------|---------------|
| `Pending` | En attente d'un PV (pas de StorageClass, ou un Pod doit d'abord l'utiliser) |
| `Bound` | Lié à un PV : prêt à l'emploi |
| `Lost` | Le PV associé a disparu |

---

## 4. Pourquoi pas un Deployment pour une base de données ?

Un Deployment traite ses Pods comme **interchangeables** : noms aléatoires, ordre de démarrage libre, tous partagent la même définition. Une base de données a des besoins différents :

| Besoin d'une base | Deployment | StatefulSet |
|-------------------|:----------:|:-----------:|
| Nom **stable** (`postgres-0`) | ❌ (`web-7d9f-abcde`) | ✅ |
| **Volume propre** à chaque Pod | ❌ (volume partagé) | ✅ |
| Démarrage **ordonné** (0, puis 1, puis 2) | ❌ | ✅ |
| Identité conservée après redémarrage | ❌ | ✅ |

---

## 5. StatefulSet

Un **StatefulSet** gère des Pods **avec état**. Il apporte trois garanties :

1. **Identité stable** : les Pods s'appellent `postgres-0`, `postgres-1`... et gardent leur nom s'ils sont recréés.
2. **Stockage stable** : chaque Pod a **son propre PVC**, qui lui est rattaché de façon permanente.
3. **Ordre** : création dans l'ordre (0, 1, 2), suppression dans l'ordre inverse.

### volumeClaimTemplates

Au lieu de créer les PVC à la main, le StatefulSet les génère à partir d'un **modèle** :

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

Pour un StatefulSet `postgres`, le PVC créé s'appelle `data-postgres-0` (nom du modèle, nom du StatefulSet, numéro).

### Service headless

Un StatefulSet s'accompagne d'un **Service headless**, c'est-à-dire sans IP virtuelle (`clusterIP: None`). Le DNS renvoie directement les IP des Pods, et donne à **chaque Pod un nom DNS stable** :

```
postgres-0.postgres.default.svc.cluster.local
```

Fichier [`manifests/postgres-service.yaml`](./manifests/postgres-service.yaml) :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - port: 5432
```

Le champ `serviceName: postgres` du StatefulSet pointe vers ce Service.

> Ton API Spring Boot continue à utiliser `jdbc:postgresql://postgres:5432/boutique` : le nom `postgres` se résout vers le Pod de la base.

### Ce que le StatefulSet ne fait PAS

⚠️ Un StatefulSet avec 3 réplicas PostgreSQL ne crée **pas** une base répliquée : ce sont **3 bases indépendantes et vides**. La réplication, les sauvegardes et la bascule automatique demandent un **opérateur** dédié (par exemple CloudNativePG ou Zalando Postgres Operator). Pour apprendre et pour le développement, **un seul réplica** suffit.

### Comportements à connaître

| Action | Conséquence |
|--------|-------------|
| Supprimer un **Pod** du StatefulSet | Il est recréé avec **le même nom** et **le même PVC** : les données sont conservées |
| Supprimer le **StatefulSet** | Les Pods disparaissent, mais **les PVC restent** (sécurité contre la perte de données) |
| Supprimer le **PVC** | Les données sont **perdues** (selon la reclaimPolicy) |
| Réduire `replicas` | Les PVC des Pods retirés sont **conservés** |

---

## 6. PostgreSQL dans Kubernetes

Fichier [`manifests/postgres-statefulset.yaml`](./manifests/postgres-statefulset.yaml), commenté :

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - name: POSTGRES_DB
              value: boutique
            - name: POSTGRES_USER
              value: boutique_app
            - name: POSTGRES_PASSWORD        # vient d'un Secret (module 04)
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

### Pourquoi `PGDATA` pointe vers un sous-dossier ?

Un volume fraîchement formaté contient souvent un dossier `lost+found` à sa racine. PostgreSQL refuse de s'initialiser dans un dossier non vide. En plaçant les données dans un **sous-dossier** (`.../data/pgdata`), on évite l'erreur.

### Variables de configuration de l'image officielle

| Variable | Rôle |
|----------|------|
| `POSTGRES_DB` | Nom de la base créée au premier démarrage |
| `POSTGRES_USER` | Utilisateur créé au premier démarrage |
| `POSTGRES_PASSWORD` | **Obligatoire** : sans elle, le conteneur refuse de démarrer |

> ⚠️ Ces variables ne sont lues qu'à la **première initialisation**. Si les données existent déjà, changer le mot de passe dans le Secret ne change pas celui de la base.

---

## 7. Se connecter à la base

**Depuis ton PC** (pour inspecter) :

```powershell
kubectl exec -it postgres-0 -- psql -U boutique_app -d boutique
```

**Depuis un autre Pod** (comme le ferait ton API), via le nom DNS :

```
postgres:5432
```

**Depuis ton PC avec un outil graphique** (DBeaver, IntelliJ) :

```powershell
kubectl port-forward pod/postgres-0 5432:5432
```

puis connecte-toi à `localhost:5432`.

---

## 8. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl get storageclass` | Liste les StorageClass |
| `kubectl get pvc` | Liste les demandes de stockage |
| `kubectl get pv` | Liste les volumes persistants |
| `kubectl describe pvc <nom>` | Détails d'un PVC (état, événements) |
| `kubectl get statefulset` (ou `sts`) | Liste les StatefulSets |
| `kubectl exec -it postgres-0 -- psql -U <user> -d <base>` | Ouvre `psql` dans le Pod |
| `kubectl port-forward pod/postgres-0 5432:5432` | Accès local à la base |
| `kubectl delete pvc <nom>` | Supprime le PVC (⚠️ et en général les données) |
| `kubectl scale statefulset postgres --replicas=N` | Change le nombre de Pods |

---

## 9. Pratique

> ⚠️ **Avec ta connexion lente :** l'image `postgres:16-alpine` fait environ **90 Mo** à télécharger, soit une quinzaine de minutes à ton débit. Lance l'étape 3 **en premier plan** puis fais autre chose pendant l'attente. Le reste du module n'utilise que `busybox:1.36`, déjà chez toi.
>
> ⚠️ **Sur Minikube, les données vivent dans le conteneur du cluster.** `minikube stop` les **conserve**, mais `minikube delete` les **détruit**. Ne fais pas `delete` entre deux sessions.

Commandes pour **PowerShell**, depuis le dossier du module.

### Étape 1 : emptyDir, un volume qui vit et meurt avec le Pod

```powershell
kubectl apply -f manifests/emptydir-pod.yaml
kubectl logs emptydir-demo -c reader --tail=5
```

Le conteneur `writer` écrit des dates, le conteneur `reader` les lit : ils **partagent** le volume.

Supprime et recrée le Pod :

```powershell
kubectl delete pod emptydir-demo
kubectl apply -f manifests/emptydir-pod.yaml
kubectl logs emptydir-demo -c reader --tail=5
```

Le fichier est reparti de zéro : un emptyDir est **perdu** avec son Pod.

### Étape 2 : un PVC qui survit au Pod

```powershell
kubectl get storageclass
kubectl apply -f manifests/pvc.yaml
kubectl get pvc
kubectl apply -f manifests/pod-pvc.yaml
kubectl get pvc,pv
kubectl logs pvc-demo
```

Le PVC est `Bound` et un PV a été créé automatiquement. Supprime le Pod et recrée-le :

```powershell
kubectl delete pod pvc-demo
kubectl apply -f manifests/pod-pvc.yaml
kubectl logs pvc-demo
```

Tu vois maintenant **deux lignes** de démarrage : la première a survécu à la suppression du Pod.

### Étape 3 : déployer PostgreSQL

```powershell
kubectl apply -f manifests/postgres-secret.yaml
kubectl apply -f manifests/postgres-service.yaml
kubectl apply -f manifests/postgres-statefulset.yaml
kubectl get pods -w
```

Attends que `postgres-0` soit `1/1 Running` (le téléchargement de l'image prend du temps). Puis :

```powershell
kubectl get statefulset
kubectl get pvc
kubectl logs postgres-0
```

Le PVC `data-postgres-0` a été créé **automatiquement**. Dans les logs, cherche `database system is ready to accept connections`.

### Étape 4 : créer des données

```powershell
kubectl exec -it postgres-0 -- psql -U boutique_app -d boutique
```

Dans `psql` :

```sql
CREATE TABLE produits (id SERIAL PRIMARY KEY, nom TEXT, prix NUMERIC);
INSERT INTO produits (nom, prix) VALUES ('Clavier', 25), ('Souris', 12);
SELECT * FROM produits;
\q
```

### Étape 5 : le test de la vérité, tuer le Pod

```powershell
kubectl delete pod postgres-0
kubectl get pods -w
```

Le StatefulSet recrée `postgres-0` avec **le même nom et le même PVC**. Quand il est prêt :

```powershell
kubectl exec -it postgres-0 -- psql -U boutique_app -d boutique -c "SELECT * FROM produits;"
```

Tes données sont toujours là. C'est tout l'intérêt du stockage persistant.

### Étape 6 : se connecter comme le ferait ton API

```powershell
kubectl run client --rm -it --image=postgres:16-alpine --restart=Never --env="PGPASSWORD=motdepasse-exemple" -- psql -h postgres -U boutique_app -d boutique -c "SELECT * FROM produits;"
```

Le client contacte la base via le nom DNS `postgres`, comme le ferait ton application.

### Étape 7 : supprimer le StatefulSet, les données restent

```powershell
kubectl delete statefulset postgres
kubectl get pods
kubectl get pvc
```

Le Pod a disparu, mais `data-postgres-0` est **toujours là**. Recrée :

```powershell
kubectl apply -f manifests/postgres-statefulset.yaml
kubectl get pods -w
kubectl exec -it postgres-0 -- psql -U boutique_app -d boutique -c "SELECT * FROM produits;"
```

Les données sont revenues.

### Étape 8 : nettoyer (⚠️ supprime les données)

```powershell
kubectl delete statefulset postgres
kubectl delete pvc data-postgres-0 demo-pvc
kubectl delete -f manifests/postgres-service.yaml
kubectl delete -f manifests/postgres-secret.yaml
kubectl delete pod pvc-demo emptydir-demo --ignore-not-found
kubectl get pv
```

Vérifie que `kubectl get pv` est vide : sans les PVC, les PV ont été supprimés.

---

## 10. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| PVC reste `Pending` | Pas de StorageClass par défaut | `kubectl get storageclass`, vérifie qu'il y a un `(default)` |
| Pod bloqué en `ContainerCreating` | Volume impossible à monter | `kubectl describe pod`, regarde les Events |
| `postgres` en `CrashLoopBackOff` avec `Database is uninitialized and superuser password is not specified` | `POSTGRES_PASSWORD` absent | Vérifie le Secret et la référence |
| `directory exists but is not empty` | Données à la racine du volume (`lost+found`) | Utilise `PGDATA` vers un sous-dossier |
| Changement de mot de passe sans effet | Les variables ne sont lues qu'à l'initialisation | Change-le avec `ALTER USER` dans `psql` |
| Données perdues après `minikube delete` | Le stockage est dans le conteneur Minikube | Normal : utilise `minikube stop` |
| PV `Released`, non réutilisable | PVC supprimé mais PV conservé (`Retain`) | Nettoyage manuel du PV |
| `postgres-1` démarre avec une base vide | Un StatefulSet ne réplique pas les données | Reste à 1 réplica ou utilise un opérateur |
| Impossible de réduire la taille d'un PVC | Un PVC ne peut qu'**augmenter** | Crée un nouveau PVC |

---

## 11. Points clés à retenir

- Le système de fichiers d'un conteneur est **éphémère** : les données importantes vont dans un **volume persistant**.
- **PVC** = la demande, **PV** = le stockage fourni, **StorageClass** = la recette qui crée les PV automatiquement.
- **emptyDir** vit avec le Pod. **PVC** survit au Pod.
- Une base de données se déploie avec un **StatefulSet** : nom stable, volume propre par Pod, ordre de démarrage.
- Le StatefulSet s'accompagne d'un **Service headless** pour des noms DNS stables.
- Supprimer un Pod ou un StatefulSet **conserve** les données. Supprimer le **PVC** les **détruit**.
- Un StatefulSet **ne réplique pas** une base : il faut un opérateur pour la haute disponibilité.
- Sur Minikube : `stop` conserve les données, `delete` les détruit.

## ✅ Checklist

- [ ] Je sais expliquer pourquoi le stockage d'un conteneur est éphémère
- [ ] Je sais distinguer emptyDir, hostPath et PVC
- [ ] Je sais expliquer PV, PVC et StorageClass
- [ ] Je sais expliquer la différence entre Deployment et StatefulSet
- [ ] Je sais déployer PostgreSQL avec un Secret, un Service headless et un StatefulSet
- [ ] J'ai prouvé que les données survivent à la suppression du Pod
- [ ] Je sais ce qui détruit les données et ce qui les conserve

**Suite :** [06 - Santé et ressources](../06-health-and-resources/README.md) (probes, requests/limits, autoscaling)