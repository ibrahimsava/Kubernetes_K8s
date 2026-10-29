# 04 - Configuration : ConfigMaps, Secrets et variables d'environnement

> **Objectif du module :** séparer la configuration du code et de l'image Docker, et gérer correctement les mots de passe et les données sensibles.

**Durée estimée :** 3 heures · **Prérequis :** modules 01 à 03 terminés, cluster Minikube démarré

---

## 1. Le problème

Imagine ton API Spring Boot. Elle a besoin de :

- l'URL de la base de données (différente en dev, test et production)
- un nom d'utilisateur et un mot de passe
- un niveau de logs, des options d'affichage, des clés d'API

Si tu écris ces valeurs **dans l'image Docker**, tu dois reconstruire l'image à chaque changement, et ton mot de passe se retrouve dans l'image et dans Git. C'est mauvais pour la sécurité et pour la souplesse.

> **Principe :** une même image doit pouvoir tourner en dev, en test et en production. Seule la **configuration** change, et elle vient de l'extérieur.

Kubernetes fournit deux ressources pour cela :

| Ressource | Pour quoi | Exemple |
|-----------|-----------|---------|
| **ConfigMap** | Configuration **non sensible** | URL, niveau de logs, nom d'application |
| **Secret** | Données **sensibles** | Mots de passe, jetons, clés d'API |

---

## 2. ConfigMap

Un **ConfigMap** est un ensemble de paires clé-valeur, ou de fichiers entiers, stocké dans le cluster.

### Trois façons de le créer

**1. Depuis un manifest** (recommandé, versionnable dans Git) :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_ENV: "dev"
  LOG_LEVEL: "info"
```

**2. Depuis des valeurs en ligne de commande :**

```bash
kubectl create configmap app-config --from-literal=APP_ENV=dev --from-literal=LOG_LEVEL=info
```

**3. Depuis un fichier :**

```bash
kubectl create configmap page-config --from-file=index.html
```

La clé est alors le nom du fichier, et la valeur son contenu.

### Limites

- Taille maximale : environ **1 Mo**.
- **Aucun chiffrement** : ne mets jamais de mot de passe dedans.

---

## 3. Secret

Un **Secret** ressemble à un ConfigMap, mais il est prévu pour les données sensibles.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:                # en clair ici, Kubernetes l'encode
  DB_USER: "admin"
  DB_PASSWORD: "motdepasse-exemple"
```

### Le point le plus important : base64 n'est pas du chiffrement

Quand tu lis un Secret, les valeurs sont en **base64** :

```bash
kubectl get secret db-secret -o yaml
```

```yaml
data:
  DB_PASSWORD: bW90ZGVwYXNzZS1leGVtcGxl
```

Le base64 est un simple **encodage**, pas une protection : n'importe qui peut le décoder en une seconde. Un Secret n'est donc pas « sûr » par lui-même. Il est mieux traité par Kubernetes que le ConfigMap (accès restreint par RBAC, non affiché dans certains outils, stockable chiffré dans etcd), mais la vraie sécurité dépend de la configuration du cluster.

### `data` ou `stringData` ?

| Champ | Contenu | Usage |
|-------|---------|-------|
| `data` | Valeurs **déjà encodées en base64** | Sorties de commandes, fichiers binaires |
| `stringData` | Valeurs **en clair** (Kubernetes les encode) | Écriture manuelle, plus pratique |

### Types de Secrets

| Type | Usage |
|------|-------|
| `Opaque` | Par défaut, données quelconques |
| `kubernetes.io/dockerconfigjson` | Identifiants pour télécharger des images d'un registry privé |
| `kubernetes.io/tls` | Certificat et clé TLS (pour l'Ingress) |

### ⚠️ Règles de sécurité pour ton repo GitHub

Ton repo est **public**. Respecte ceci :

- **Ne commite jamais** de vrais mots de passe, clés d'API ou jetons.
- Dans les fichiers d'exemple, mets des valeurs **bidon** (`motdepasse-exemple`), comme dans `secret.yaml`.
- Si tu as un vrai fichier de secrets en local, ajoute-le à `.gitignore` :

```
# .gitignore
secret-real.yaml
*.secret.yaml
.env
```

- En production, on utilise des outils dédiés (Sealed Secrets, External Secrets, HashiCorp Vault). Tu les verras plus tard.

---

## 4. Utiliser la configuration dans un Pod

Il y a **deux grandes méthodes** : des **variables d'environnement**, ou des **fichiers montés**.

### Méthode 1 : variables d'environnement

**Toutes les clés d'un coup, avec `envFrom` :**

```yaml
containers:
  - name: app
    image: nginx:1.27
    envFrom:
      - configMapRef:
          name: app-config      # APP_ENV, LOG_LEVEL... deviennent des variables
      - secretRef:
          name: db-secret       # DB_USER, DB_PASSWORD...
```

**Une clé précise, avec `valueFrom` :**

```yaml
env:
  - name: DB_PASSWORD           # nom de la variable dans le conteneur
    valueFrom:
      secretKeyRef:
        name: db-secret         # nom du Secret
        key: DB_PASSWORD        # clé dans le Secret
```

Même principe avec `configMapKeyRef` pour un ConfigMap.

| | `envFrom` | `valueFrom` |
|---|-----------|-------------|
| Portée | Toutes les clés | Une seule clé |
| Renommage | Non, la clé devient le nom | Oui, tu choisis le nom |
| Usage | Rapide, beaucoup de variables | Contrôle précis |

### Méthode 2 : fichiers montés (volumes)

Chaque clé devient un **fichier** dans un dossier du conteneur :

```yaml
containers:
  - name: nginx
    image: nginx:1.27
    volumeMounts:
      - name: page
        mountPath: /usr/share/nginx/html     # dossier dans le conteneur
volumes:
  - name: page
    configMap:
      name: page-config                      # une clé = un fichier
```

Utile pour les fichiers de configuration complets (`application.properties`, `nginx.conf`, certificats).

### Variables ou fichiers : lequel choisir ?

| Critère | Variables d'environnement | Fichiers montés |
|---------|--------------------------|-----------------|
| Simplicité | ✅ Très simple | Un peu plus long |
| Mise à jour sans redémarrage | ❌ Non, lues au démarrage | ✅ Oui, le fichier se met à jour (environ 1 minute) |
| Fichiers complets | ❌ | ✅ |
| Visibilité des secrets | Visibles par `env` dans le conteneur | Visibles dans un fichier, droits réglables |

### ⚠️ Piège important : la mise à jour

- Modifier un ConfigMap **ne change pas** les variables d'environnement d'un Pod déjà démarré. Il faut **redémarrer** les Pods :
  ```bash
  kubectl rollout restart deployment/web-config
  ```
- Les **fichiers montés** se mettent à jour automatiquement après environ une minute, mais ton application doit relire le fichier pour en tenir compte. (L'exception : un montage avec `subPath` ne se met **jamais** à jour.)

---

## 5. Cas concret : une application Spring Boot

Spring Boot sait lire sa configuration depuis des **variables d'environnement**. Le nom de la variable se déduit de la propriété :

| Propriété `application.properties` | Variable d'environnement |
|-----------------------------------|--------------------------|
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `spring.datasource.username` | `SPRING_DATASOURCE_USERNAME` |
| `spring.datasource.password` | `SPRING_DATASOURCE_PASSWORD` |
| `spring.profiles.active` | `SPRING_PROFILES_ACTIVE` |

Il suffit de séparer les valeurs :

- ce qui n'est pas sensible dans un **ConfigMap** (URL, profil)
- le mot de passe dans un **Secret**

```yaml
envFrom:
  - configMapRef:
      name: api-config        # URL, profil, utilisateur
  - secretRef:
      name: api-secret        # mot de passe
```

Un exemple complet est fourni dans [`manifests/spring-boot-exemple.yaml`](./manifests/spring-boot-exemple.yaml). Remarque : l'URL utilise `postgres` comme hôte, le nom DNS du Service de la base (module 03).

Résultat : **la même image** tourne partout. Tu changes juste le ConfigMap et le Secret selon l'environnement.

---

## 6. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl create configmap <nom> --from-literal=K=V` | Crée un ConfigMap |
| `kubectl create configmap <nom> --from-file=<fichier>` | Crée depuis un fichier |
| `kubectl create secret generic <nom> --from-literal=K=V` | Crée un Secret |
| `kubectl get configmaps` / `kubectl get secrets` | Liste |
| `kubectl describe configmap <nom>` | Contenu d'un ConfigMap |
| `kubectl describe secret <nom>` | Clés d'un Secret (sans les valeurs) |
| `kubectl get secret <nom> -o yaml` | Secret avec valeurs en base64 |
| `kubectl exec <pod> -- env` | Variables d'environnement d'un Pod |
| `kubectl rollout restart deployment/<nom>` | Redémarre pour recharger les variables |

### Encoder et décoder en base64 sous PowerShell

```powershell
# Encoder
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("monmotdepasse"))

# Décoder
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("bW9ubW90ZGVwYXNzZQ=="))
```

---

## 7. Pratique

> Toutes les images utilisées (`nginx:1.27`, `busybox:1.36`) sont déjà téléchargées chez toi : pas de téléchargement lourd dans ce module.

Commandes pour **PowerShell**, depuis le dossier du module.

### Étape 1 : Créer les ConfigMaps et le Secret

```powershell
kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/secret.yaml
kubectl get configmaps
kubectl get secrets
kubectl describe configmap app-config
kubectl describe secret db-secret
```

Remarque : `describe secret` montre les noms des clés et leur taille, **jamais** les valeurs.

### Étape 2 : Constater que le Secret n'est que du base64

```powershell
kubectl get secret db-secret -o yaml
kubectl get secret db-secret -o jsonpath='{.data.DB_PASSWORD}'
```

Décode la valeur obtenue :

```powershell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("<valeur-obtenue>"))
```

Tu retrouves le mot de passe en clair, ce qui montre pourquoi un Secret n'est pas un coffre-fort.

### Étape 3 : Injecter la configuration en variables d'environnement

```powershell
kubectl apply -f manifests/pod-env.yaml
kubectl logs env-demo
```

Tu vois `APP_ENV`, `APP_NAME`, `LOG_LEVEL`, `DB_USER` et `DB_PASSWORD` : la configuration est bien arrivée dans le conteneur.

### Étape 4 : Monter la configuration en fichiers

```powershell
kubectl apply -f manifests/deployment-config.yaml
kubectl get pods -l app=web-config
kubectl exec deploy/web-config -- ls /usr/share/nginx/html
kubectl exec deploy/web-config -- ls /etc/secrets
kubectl exec deploy/web-config -- cat /etc/secrets/DB_PASSWORD
kubectl port-forward deployment/web-config 8080:80
```

Ouvre http://localhost:8080 : la page « Configuration v1 » vient du ConfigMap, pas de l'image. Arrête avec `Ctrl+C`.

### Étape 5 : Modifier le ConfigMap et observer

Édite `manifests/configmap.yaml` : change `Configuration v1` en `Configuration v2` dans la clé `index.html`, ainsi que `APP_ENV: "dev"` en `APP_ENV: "prod"`. Puis :

```powershell
kubectl apply -f manifests/configmap.yaml
```

Attends environ **1 à 2 minutes**, puis compare :

```powershell
kubectl exec deploy/web-config -- cat /usr/share/nginx/html/index.html
kubectl exec deploy/web-config -- env
```

Le **fichier** affiche v2, mais la **variable** `APP_ENV` vaut encore `dev`.

### Étape 6 : Redémarrer pour recharger les variables

```powershell
kubectl rollout restart deployment/web-config
kubectl rollout status deployment/web-config
kubectl exec deploy/web-config -- env
```

Cette fois `APP_ENV` vaut `prod`.

### Étape 7 : Nettoyer

```powershell
kubectl delete -f manifests/deployment-config.yaml
kubectl delete -f manifests/pod-env.yaml
kubectl delete -f manifests/secret.yaml
kubectl delete -f manifests/configmap.yaml
```

---

## 8. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| Pod en `CreateContainerConfigError` | ConfigMap ou Secret **introuvable**, ou clé inexistante | `kubectl describe pod`, lis les Events, vérifie le nom et la clé |
| Variable vide ou absente | Mauvais nom de clé dans `valueFrom` | Compare avec `kubectl describe configmap` |
| Changement du ConfigMap sans effet | Variables lues seulement au démarrage | `kubectl rollout restart` |
| Fichier monté pas à jour | Délai de synchronisation, ou montage avec `subPath` | Attends environ 1 minute, ou évite `subPath` |
| Dossier du conteneur écrasé par le montage | Le volume **remplace** tout le dossier cible | Monte dans un dossier dédié, ou utilise `subPath` pour un seul fichier |
| `illegal base64 data` | Valeur non encodée dans `data` | Utilise `stringData` ou encode correctement |
| Mot de passe publié sur GitHub | Secret commité dans Git | Révoque-le immédiatement et change-le, puis nettoie l'historique |

---

## 9. Points clés à retenir

- On **sépare la configuration de l'image** : une même image tourne dans tous les environnements.
- **ConfigMap** pour le non sensible, **Secret** pour le sensible.
- Un Secret est en **base64, pas chiffré** : ce n'est pas un coffre-fort. Ne commite jamais de vrais secrets dans Git.
- Deux façons de consommer : **variables d'environnement** (`envFrom`, `valueFrom`) ou **fichiers montés**.
- Les variables ne se mettent à jour qu'au **redémarrage** des Pods, les fichiers montés se mettent à jour tout seuls.
- Spring Boot lit naturellement `SPRING_DATASOURCE_URL` et consorts : ConfigMap + Secret suffisent.

## ✅ Checklist

- [ ] Je sais expliquer pourquoi on externalise la configuration
- [ ] Je sais créer un ConfigMap et un Secret de trois façons
- [ ] Je sais expliquer pourquoi un Secret n'est pas chiffré par défaut
- [ ] Je sais injecter la configuration par variables d'environnement et par fichiers
- [ ] Je sais pourquoi un changement de ConfigMap nécessite parfois un redémarrage
- [ ] Je sais configurer une application Spring Boot avec un ConfigMap et un Secret
- [ ] Je sais protéger mon repo contre la fuite de secrets

**Suite :** [05 - Stockage](../05-storage/README.md) (Volumes, PV/PVC, PostgreSQL avec StatefulSet)