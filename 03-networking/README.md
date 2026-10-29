# 03 - Réseau : Services, DNS et Ingress

> **Objectif du module :** rendre tes applications accessibles de façon stable, à l'intérieur du cluster comme depuis l'extérieur.

**Durée estimée :** 3 à 4 heures · **Prérequis :** modules 01 et 02 terminés, cluster Minikube démarré

---

## 1. Le problème

Au module 02, tu as vu que les Pods sont **éphémères** : ils meurent, sont recréés, et chaque nouveau Pod reçoit une **nouvelle adresse IP**.

```
Pod web-abc  (10.244.0.5)   ← supprimé
Pod web-xyz  (10.244.0.9)   ← nouveau, autre IP !
```

Si ton API Spring Boot veut parler à ta base de données ou à un autre service, elle ne peut pas écrire une IP de Pod en dur. Il faut aussi répartir le trafic entre plusieurs Pods identiques, et exposer l'application à l'extérieur.

Kubernetes résout cela avec deux ressources :

| Ressource | Rôle |
|-----------|------|
| **Service** | Une adresse et un nom **stables**, qui répartissent le trafic vers un groupe de Pods |
| **Ingress** | Des règles de routage **HTTP** depuis l'extérieur vers plusieurs Services |

---

## 2. Le Service

Un **Service** est un point d'entrée stable devant un groupe de Pods. Il possède :

- une **IP virtuelle** qui ne change pas (la ClusterIP)
- un **nom DNS** (par exemple `web`)
- un **selector** de labels pour retrouver ses Pods

```
        Client
          │
          ▼
   Service "web"  (10.96.45.12, DNS : web)
   selector: app=web
          │  répartition de charge
    ┌─────┼─────┐
    ▼     ▼     ▼
  Pod 1  Pod 2  Pod 3      (label app=web)
```

C'est le même mécanisme de **labels et selectors** que pour le Deployment : le Service ne connaît pas les Pods par leur nom, il prend tous ceux qui ont le bon label.

### Manifest

Fichier [`manifests/service-clusterip.yaml`](./manifests/service-clusterip.yaml) :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP          # type par défaut
  selector:
    app: web               # tous les Pods avec ce label
  ports:
    - port: 80             # port du Service
      targetPort: 80       # port du conteneur
      protocol: TCP
```

### Les ports à ne pas confondre

| Champ | Signification |
|-------|---------------|
| `port` | Le port sur lequel le **Service** écoute |
| `targetPort` | Le port du **conteneur** vers lequel le trafic est envoyé |
| `nodePort` | (NodePort uniquement) Le port ouvert sur le **nœud**, entre 30000 et 32767 |

Exemple : une API Spring Boot écoute sur `8080` dans le conteneur, et tu veux l'exposer sur `80` :

```yaml
ports:
  - port: 80
    targetPort: 8080
```

---

## 3. Les types de Service

| Type | Accessible depuis | Usage |
|------|-------------------|-------|
| **ClusterIP** | L'intérieur du cluster seulement | Communication entre services (API → base de données). Le plus courant. |
| **NodePort** | L'extérieur, via `IP-du-nœud:nodePort` | Tests et développement |
| **LoadBalancer** | L'extérieur, via un load balancer du cloud | Production sur AWS, GCP, Azure |
| **ExternalName** | L'intérieur | Alias DNS vers un service externe |

Ils sont **emboîtés** : NodePort inclut un ClusterIP, et LoadBalancer inclut un NodePort.

```
LoadBalancer ⊃ NodePort ⊃ ClusterIP
```

### NodePort

```yaml
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080      # optionnel, sinon choisi automatiquement
```

### LoadBalancer sur Minikube

Dans le cloud, un LoadBalancer reçoit une IP publique automatiquement. Sur Minikube, il reste en `<pending>` tant que tu n'as pas lancé `minikube tunnel` dans un terminal séparé.

### Et dans un vrai projet ?

On expose rarement chaque Service en LoadBalancer, car cela coûte une IP publique par service. On met plutôt **un seul point d'entrée** (l'Ingress) devant plusieurs Services de type ClusterIP.

---

## 4. Comment ça marche : Endpoints et kube-proxy

### EndpointSlices

Kubernetes tient à jour automatiquement la **liste des IP de Pods** derrière chaque Service, dans des objets appelés **EndpointSlices** (les anciens `Endpoints` ont été remplacés par eux dans les versions récentes).

```bash
kubectl describe service web                              # ligne "Endpoints"
kubectl get endpointslices -l kubernetes.io/service-name=web
```

Un Pod n'est dans la liste que si :
1. son label correspond au `selector` du Service
2. il est **prêt** (`Ready`)

Si le selector ne correspond à aucun Pod, la liste est **vide** et le Service ne répond pas : c'est l'erreur la plus courante.

### kube-proxy

Sur chaque nœud, **kube-proxy** programme des règles réseau (iptables ou IPVS) qui redirigent le trafic envoyé à l'IP virtuelle du Service vers l'un des Pods. L'IP du Service est **virtuelle** : aucun processus n'écoute dessus, ce sont uniquement des règles de redirection.

---

## 5. Le DNS dans le cluster

Kubernetes inclut un serveur DNS (**CoreDNS**) qui crée automatiquement un nom pour chaque Service :

```
<service>.<namespace>.svc.cluster.local
```

| Depuis | Nom à utiliser |
|--------|----------------|
| Le **même namespace** | `web` |
| Un **autre namespace** | `web.default` ou `web.default.svc.cluster.local` |

C'est ce qui te permet, dans ton application, de configurer simplement :

```
spring.datasource.url=jdbc:postgresql://postgres:5432/mabase
```

Ici, `postgres` est le nom du Service de la base de données. Aucune IP à gérer.

---

## 6. Ingress

Un **Ingress** définit des règles de routage **HTTP/HTTPS** vers tes Services, avec un seul point d'entrée :

```
                    Internet
                       │
                       ▼
               ┌──── Ingress ────┐
               │ web.local → web │
               │ api.local → api │
               └───┬─────────┬───┘
                   ▼         ▼
              Service web  Service api
```

Un Ingress est seulement un ensemble de **règles**. Pour les appliquer, il faut un **Ingress Controller** installé dans le cluster (le plus courant est **ingress-nginx**). Sans controller, l'Ingress ne fait rien.

Fichier [`manifests/ingress.yaml`](./manifests/ingress.yaml) :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: main-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: web.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
    - host: api.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
```

| Notion | Description |
|--------|-------------|
| **Routage par hôte** | `web.local` et `api.local` vont vers des Services différents |
| **Routage par chemin** | `/shop` et `/blog` vont vers des Services différents (nécessite parfois une réécriture d'URL) |
| **TLS** | Un Ingress peut gérer le HTTPS avec un certificat (vu avec cert-manager plus tard) |

> 💡 Le projet **Gateway API** est le successeur de l'Ingress. Tu verras les deux en entreprise, mais l'Ingress reste le plus répandu pour débuter.

---

## 7. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl get services` (ou `svc`) | Liste les Services |
| `kubectl describe svc web` | Détails, selector et Endpoints |
| `kubectl get endpointslices -l kubernetes.io/service-name=web` | Voir les IP de Pods derrière le Service |
| `kubectl expose deployment web --port=80` | Crée un Service pour un Deployment (impératif) |
| `kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh` | Pod temporaire pour tester depuis l'intérieur |
| `kubectl port-forward svc/web 8080:80` | Redirige un port local vers un Service |
| `minikube service web-nodeport --url` | Donne l'URL d'un Service NodePort sur Minikube |
| `minikube tunnel` | Donne une IP aux Services LoadBalancer |
| `minikube addons enable ingress` | Installe l'Ingress Controller |
| `kubectl get ingress` | Liste les Ingress |

---

## 8. Pratique

> ⚠️ **Avec ta connexion lente :** les étapes 1 à 7 n'utilisent que des images déjà téléchargées (`nginx:1.27`, `busybox:1.36`). **L'étape 8 (Ingress) est la seule lourde** : l'installation de l'Ingress Controller télécharge plusieurs images depuis `registry.k8s.io`. Fais-la quand ta connexion est bonne, ou remets-la à plus tard : le reste du module reste valable sans elle.

Les commandes ci-dessous sont pour **PowerShell**.

### Étape 1 : Déployer l'application

```powershell
kubectl apply -f manifests/deployment.yaml
kubectl get pods -o wide
```

Note les IP des 3 Pods : elles sont différentes.

### Étape 2 : Créer le Service

```powershell
kubectl apply -f manifests/service-clusterip.yaml
kubectl get svc
kubectl describe svc web
```

Repère dans `describe` le **selector** et la ligne **Endpoints** : tu dois y voir les 3 IP des Pods.

```powershell
kubectl get endpointslices -l kubernetes.io/service-name=web
```

### Étape 3 : Tester depuis l'intérieur du cluster

Le Service n'est accessible que depuis le cluster. Lance un Pod temporaire :

```powershell
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web
```

Tu dois voir la page HTML de Nginx. Le nom `web` a été résolu par le DNS du cluster.

### Étape 4 : Rendre chaque Pod identifiable

Pour voir la répartition de charge, on fait afficher à chaque Pod **son propre nom** :

```powershell
kubectl get pods -l app=web -o name | ForEach-Object { kubectl exec $_ -- sh -c 'hostname > /usr/share/nginx/html/index.html' }
```

> Cette modification vit dans le Pod : si le Pod est recréé, elle disparaît. C'est un outil de test, pas une pratique de production.

### Étape 5 : Observer la répartition de charge

```powershell
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://web; done'
```

Tu dois voir **les noms de différents Pods** : le Service répartit les requêtes.

### Étape 6 : Explorer le DNS

```powershell
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web.default.svc.cluster.local
```

Compare l'IP obtenue avec la colonne `CLUSTER-IP` de `kubectl get svc`.

### Étape 7 : Exposer avec un NodePort

```powershell
kubectl apply -f manifests/service-nodeport.yaml
kubectl get svc
minikube service web-nodeport --url
```

Minikube affiche une URL du type `http://127.0.0.1:xxxxx`. **Laisse le terminal ouvert** (avec le driver Docker sur Windows, le tunnel reste actif tant que la commande tourne), et ouvre l'URL dans ton navigateur. Rafraîchis plusieurs fois : tu vois les noms des Pods changer.

### Étape 8 (optionnelle, lourde) : Ingress

**8a. Installer l'Ingress Controller**

```powershell
minikube addons enable ingress
kubectl get pods -n ingress-nginx
```

Attends que le Pod `ingress-nginx-controller-...` soit `Running` (cela peut prendre plusieurs minutes à ton débit).

**8b. Créer le deuxième service (`api`) et l'Ingress**

```powershell
kubectl apply -f manifests/api.yaml
kubectl apply -f manifests/ingress.yaml
kubectl get ingress
```

**8c. Tester**

Fais une redirection de port vers le controller, dans un terminal qui reste ouvert :

```powershell
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8081:80
```

Dans un **autre** terminal, envoie des requêtes avec un en-tête `Host` différent :

```powershell
curl.exe -H "Host: web.local" http://localhost:8081
curl.exe -H "Host: api.local" http://localhost:8081
```

Tu obtiens des réponses de Services différents, avec une seule entrée.

### Étape 9 : Nettoyer

```powershell
kubectl delete -f manifests/ingress.yaml --ignore-not-found
kubectl delete -f manifests/api.yaml --ignore-not-found
kubectl delete -f manifests/service-nodeport.yaml
kubectl delete -f manifests/service-clusterip.yaml
kubectl delete -f manifests/deployment.yaml
```

---

## 9. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| Le Service ne répond pas, Endpoints vides | Le `selector` ne correspond à aucun Pod (faute de frappe dans un label) | Compare `kubectl describe svc` avec `kubectl get pods --show-labels` |
| `Connection refused` | Mauvais `targetPort` (le conteneur n'écoute pas sur ce port) | Vérifie le port réellement utilisé par l'application |
| Service OK mais Pod absent des Endpoints | Le Pod n'est pas `Ready` | `kubectl describe pod`, regarde les probes (module 06) |
| `EXTERNAL-IP` reste `<pending>` | Normal sur Minikube sans tunnel | Lance `minikube tunnel` |
| Le nom `web` ne se résout pas | Tu es dans un autre namespace | Utilise `web.<namespace>` |
| Ingress sans effet, `ADDRESS` vide | Pas d'Ingress Controller installé, ou `ingressClassName` absent | `minikube addons enable ingress` |
| 404 depuis l'Ingress | L'en-tête `Host` ne correspond à aucune règle | Ajoute `-H "Host: web.local"` |

---

## 10. Points clés à retenir

- Les Pods sont éphémères : on passe par un **Service** pour une adresse et un nom **stables**.
- Un Service retrouve ses Pods avec un **selector de labels**, et ne route que vers les Pods **prêts**.
- **ClusterIP** : interne. **NodePort** : test. **LoadBalancer** : cloud. L'**Ingress** : un seul point d'entrée HTTP devant plusieurs Services.
- Dans le cluster, un Service est joignable par son **nom DNS** : `web`, `web.default`, `web.default.svc.cluster.local`.
- Un Ingress n'est qu'un ensemble de règles : il faut un **Ingress Controller** pour qu'elles s'appliquent.
- Si un Service ne répond pas, vérifie d'abord ses **Endpoints**.

## ✅ Checklist

- [ ] Je sais expliquer pourquoi on ne parle pas directement aux Pods
- [ ] Je sais écrire un Service et distinguer `port`, `targetPort` et `nodePort`
- [ ] Je sais choisir entre ClusterIP, NodePort et LoadBalancer
- [ ] Je sais diagnostiquer un Service sans Endpoints
- [ ] Je sais résoudre un Service par son nom DNS depuis un Pod
- [ ] Je sais expliquer le rôle d'un Ingress et d'un Ingress Controller

**Suite :** [04 - Configuration](../04-configuration/README.md) (ConfigMaps, Secrets, variables d'environnement)