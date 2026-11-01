# Exercices - Module 07

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 Toutes les images utilisées (`nginx:1.27`, `busybox:1.36`) sont déjà chez toi : pas de téléchargement lourd.
>
> Commandes pour **PowerShell**. Utilise des guillemets **simples** autour des expressions contenant `$`, `{}` ou des espaces dans les selectors.
>
> ⚠️ Avant chaque commande de suppression, vérifie ton namespace : `kubectl config view --minify` (cherche `namespace`).

---

## Exercice 1 : Explorer les namespaces

1. Liste les namespaces : `kubectl get ns --show-labels`.
2. Liste les Pods de `kube-system` : `kubectl get pods -n kube-system`.
3. Liste les types de ressources avec et sans namespace :
   ```powershell
   kubectl api-resources --namespaced=true
   kubectl api-resources --namespaced=false
   ```
4. Applique `manifests/namespaces.yaml`.

**Questions**
- Cite trois ressources **sans** namespace. Pourquoi ne peuvent-elles pas en avoir ?
- Pourquoi `kubectl get pods` ne montre-t-il pas les Pods de `kube-system` ?
- Que fait l'option `-A` ?

---

## Exercice 2 : Deux environnements, mêmes noms

1. Applique `manifests/app.yaml` dans `dev`, puis dans `test`.
2. Liste : `kubectl get deployments,services -A`.
3. Supprime le Deployment `web` de `dev` uniquement et vérifie que celui de `test` est intact.
4. Recrée celui de `dev`.

**Questions**
- Pourquoi n'y a-t-il aucun conflit entre les deux `web` ?
- Que se passe-t-il si tu appliques le fichier **sans** `-n` ? Dans quel namespace atterrit-il ?

---

## Exercice 3 : DNS entre namespaces

1. Depuis un Pod temporaire du namespace `test`, atteins le Service `web` de `test` puis celui de `dev`.
   ```powershell
   kubectl run tmp -n test --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web
   kubectl run tmp -n test --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web.dev
   ```
2. Résous les noms avec `nslookup web`, `nslookup web.dev` et `nslookup web.dev.svc.cluster.local`.
3. Essaie `http://web.prod` : que se passe-t-il ?

**Questions**
- Comment distingues-tu quel `web` a répondu ? (Indice : modifie le contenu d'un des deux avec `kubectl exec`.)
- Comment ton API Spring Boot dans `app` accéderait-elle à la base `postgres` du namespace `data` ?
- Les namespaces isolent-ils le réseau par défaut ? Qu'est-ce qu'il faudrait ajouter ?

---

## Exercice 4 : Contexte et namespace par défaut

1. Affiche tes contextes : `kubectl config get-contexts`.
2. Passe à `dev` par défaut : `kubectl config set-context --current --namespace=dev`.
3. Lance `kubectl get pods` sans `-n`. Que vois-tu ?
4. **Remets** le namespace à `default`.

**Questions**
- Pourquoi cette habitude est-elle risquée si on l'oublie ?
- Comment éviter de supprimer des ressources dans le mauvais cluster ?

---

## Exercice 5 : Labels et selectors

1. Affiche les labels des Pods de `dev` : `kubectl get pods -n dev --show-labels`.
2. Ajoute les labels d'environnement :
   ```powershell
   kubectl label pods -l app=web env=dev -n dev
   kubectl label pods -l app=web env=test -n test
   ```
3. Écris les commandes pour :
   - lister les Pods de **tous** les namespaces avec `env=dev`
   - lister ceux dont `env` est `dev` **ou** `test`
   - lister ceux dont `env` n'est **pas** `dev`
   - lister ceux qui ont le label `tier` quelle que soit sa valeur
   - lister ceux de l'application `boutique` (label `app.kubernetes.io/part-of`)
4. Retire le label `env` d'un Pod, puis rajoute-le avec une autre valeur (`--overwrite`).

**Questions**
- Pourquoi les labels posés avec `kubectl label` sur un Pod disparaissent-ils quand le Pod est recréé ?
- Où faut-il mettre un label pour qu'il soit conservé ?
- Quelle différence entre un label et une annotation ?

---

## Exercice 6 : Supprimer un namespace

1. Crée un namespace jetable avec des ressources :
   ```powershell
   kubectl create namespace jetable
   kubectl create deployment demo --image=nginx:1.27 -n jetable
   kubectl create configmap cfg --from-literal=A=1 -n jetable
   kubectl create secret generic sec --from-literal=B=2 -n jetable
   kubectl get all,cm,secret -n jetable
   ```
2. Supprime le namespace : `kubectl delete namespace jetable`.
3. Vérifie ce qu'il en reste.

**Questions**
- Que devient chaque ressource ?
- Pourquoi supprimer un namespace est-il une commande dangereuse en production ?
- Quels objets **cluster-wide** pourraient survivre à la suppression d'un namespace ?

---

## Exercice 7 : Quotas et LimitRange 🔧

1. Applique `manifests/limitrange.yaml` puis `manifests/quota.yaml`.
2. Redémarre le Deployment de `dev` : `kubectl rollout restart deployment/web -n dev`.
3. Vérifie, avec `kubectl describe pod`, que les nouveaux Pods ont des `Requests` et `Limits` que tu n'as jamais écrites.
4. Affiche `kubectl describe quota quota-dev -n dev`.
5. Passe à 6 réplicas, puis cherche la raison dans `kubectl describe rs -n dev`.
6. Modifie `quota.yaml` (par exemple `pods: "10"`), réapplique, et observe.

**Questions**
- Combien de Pods sont créés, et pourquoi pas 6 ?
- Qui a ajouté les `Requests` et `Limits` aux Pods : le Deployment, le LimitRange ou le quota ?
- Que se passerait-il si tu supprimais le **LimitRange** en gardant le quota sur le CPU et la mémoire ?
- Dans quel ordre le scheduler, le quota et le LimitRange interviennent-ils ?

---

## Exercice 8 : RBAC, comprendre un existant

1. Applique `manifests/rbac.yaml`.
2. Pour `lecteur` (namespace `dev`), réponds **avant** de tester, puis vérifie avec `kubectl auth can-i ... --as=system:serviceaccount:dev:lecteur` :
   - lister les Pods de `dev`
   - supprimer un Pod de `dev`
   - lister les Pods de `test`
   - lire les logs d'un Pod de `dev`
   - lister les Secrets de `dev`
   - lister les Deployments de `dev`
3. Lance `kubectl auth can-i --list -n dev --as=system:serviceaccount:dev:lecteur`.

**Questions**
- Pourquoi le droit sur les logs nécessite-t-il `pods/log` en plus de `pods` ?
- Pourquoi `lecteur` ne peut-il rien faire dans `test`, alors que le namespace existe ?
- Que veut dire `apiGroups: [""]` ?

---

## Exercice 9 : RBAC, écrire le tien 🔧

Écris un manifest `rbac-config.yaml` qui crée, dans `dev` :

- un ServiceAccount `config-admin`
- un Role `gestion-configmaps` qui permet **de tout faire sur les ConfigMaps** (`get`, `list`, `watch`, `create`, `update`, `patch`, `delete`) et **rien d'autre**
- un RoleBinding qui relie les deux

Puis démontre avec `kubectl auth can-i` que :

- il peut créer et supprimer des ConfigMaps dans `dev`
- il ne peut **pas** lire les Secrets de `dev`
- il ne peut **pas** créer de Pods
- il ne peut **rien** faire dans `test`

**Bonus :** remplace le Role par le ClusterRole prédéfini `edit` dans un RoleBinding, et compare les droits obtenus (`can-i --list`).

---

## Exercice 10 : Role ou ClusterRole ?

Pour chaque besoin, indique le type d'objet et le type de binding à utiliser :

1. Un développeur qui doit lire les Pods du namespace `dev` seulement.
2. Un outil de supervision qui doit lire les Pods de **tous** les namespaces.
3. Un administrateur qui doit gérer les Nodes (ressource cluster-wide).
4. Un pipeline CI/CD qui met à jour les Deployments de `dev` et rien d'autre (voir `manifests/rbac-deployer.yaml`).

**Questions**
- Pourquoi un `RoleBinding` qui référence un `ClusterRole` ne donne-t-il des droits que dans un namespace ?
- Pourquoi donner `cluster-admin` à un pipeline est-il une mauvaise idée, même si « ça marche » ?
- Que se passe-t-il si ce pipeline est compromis dans chacun des deux cas ?

---

## Questions d'auto-évaluation

1. Qu'est-ce qu'un namespace, et que n'est-il **pas** (en termes de sécurité) ?
2. Quelles ressources ne sont pas rattachées à un namespace ?
3. Comment un Pod du namespace `app` joint-il un Service du namespace `data` ?
4. Quelle différence entre un label et une annotation ?
5. Quel est le rôle d'un ResourceQuota ? D'un LimitRange ?
6. Quelle est la différence entre un Role, un ClusterRole, un RoleBinding et un ClusterRoleBinding ?
7. Pourquoi dit-on que les permissions RBAC sont « additives » ?
8. Comment tester les droits d'un ServiceAccount sans se connecter avec ?
9. Pourquoi un pipeline CI/CD doit-il avoir son propre ServiceAccount ?

---

## Nettoyage

```powershell
kubectl delete namespace dev test jetable --ignore-not-found
kubectl config set-context --current --namespace=default
kubectl get ns
```