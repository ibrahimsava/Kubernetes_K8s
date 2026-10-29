# Exercices - Module 05

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 Seul PostgreSQL demande un téléchargement important (`postgres:16-alpine`, environ 90 Mo). Une fois l'image téléchargée, tout le reste est rapide.
>
> ⚠️ **Ne fais pas `minikube delete`** pendant ce module : tu perdrais toutes les données des volumes. Utilise `minikube stop` pour arrêter.
>
> Commandes pour **PowerShell**. Utilise de **fausses** valeurs pour les mots de passe.

---

## Exercice 1 : emptyDir

1. Applique `manifests/emptydir-pod.yaml`.
2. Lis les logs du conteneur `reader` : `kubectl logs emptydir-demo -c reader --tail=5`.
3. Supprime le Pod, recrée-le et relis les logs.

**Questions**
- Pourquoi les deux conteneurs voient-ils les mêmes fichiers ?
- Le fichier survit-il à la suppression du Pod ? Et à un simple redémarrage d'un conteneur ?
- Cite deux cas d'usage d'un `emptyDir`.

---

## Exercice 2 : Premier PVC

1. Affiche les StorageClass : `kubectl get storageclass`. Laquelle est par défaut ?
2. Applique `manifests/pvc.yaml`, puis `kubectl get pvc` et `kubectl get pv`.
3. Applique `manifests/pod-pvc.yaml` et relance `kubectl get pvc,pv`.
4. Supprime le Pod `pvc-demo`, recrée-le, et lis ses logs.

**Questions**
- Quel est le statut du PVC **avant** et **après** l'application du Pod ? (Selon la StorageClass, il peut déjà être `Bound`.)
- Qui a créé le PV : toi, ou la StorageClass ?
- Combien de lignes `Demarrage` vois-tu après la recréation ? Pourquoi ?

---

## Exercice 3 : Inspecter un PVC et un PV

1. `kubectl describe pvc demo-pvc` : note le `StorageClass`, le `Volume`, les `Access Modes` et la `Capacity`.
2. `kubectl describe pv <nom-du-pv>` : note le `Reclaim Policy` et le chemin sur le nœud.
3. `kubectl get pv <nom> -o yaml` : repère le lien (`claimRef`) vers le PVC.

**Questions**
- Quelle est la politique de récupération (`Reclaim Policy`) ?
- Que va-t-il se passer pour le PV et les données si tu supprimes le PVC ?
- Pourquoi `ReadWriteOnce` est-il suffisant pour une base de données ?

---

## Exercice 4 : Déployer PostgreSQL

1. Applique le Secret, le Service headless, puis le StatefulSet (dans cet ordre).
2. Suis le démarrage avec `kubectl get pods -w`.
3. Lis les logs et trouve la ligne `ready to accept connections`.
4. Affiche `kubectl get sts,pvc,pv`.

**Questions**
- Comment s'appelle le Pod ? Le PVC ? Pourquoi ces noms ?
- Pourquoi le Service est-il de type headless (`clusterIP: None`) ?
- Que se passerait-il si tu avais oublié `POSTGRES_PASSWORD` ?

---

## Exercice 5 : La preuve de la persistance 🔧

1. Ouvre `psql` : `kubectl exec -it postgres-0 -- psql -U boutique_app -d boutique`.
2. Crée une table `clients` avec 3 lignes de ton choix, puis quitte.
3. Supprime le Pod : `kubectl delete pod postgres-0`.
4. Attends qu'il soit recréé et vérifie que tes données sont là.
5. Supprime ensuite le **StatefulSet** (`kubectl delete statefulset postgres`), puis recrée-le avec `kubectl apply`. Vérifie à nouveau les données.

**Questions**
- Le Pod recréé a-t-il le même nom ? La même IP ? Le même PVC ?
- Que contient `kubectl get pvc` quand le StatefulSet est supprimé ?
- Dans quel cas précis perdrais-tu les données ?

---

## Exercice 6 : Se connecter comme une application

1. Depuis un Pod client, interroge la base via son nom DNS :
   ```powershell
   kubectl run client --rm -it --image=postgres:16-alpine --restart=Never --env="PGPASSWORD=motdepasse-exemple" -- psql -h postgres -U boutique_app -d boutique -c "SELECT * FROM clients;"
   ```
2. Résous le nom DNS du Pod lui-même avec busybox :
   ```powershell
   kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup postgres-0.postgres.default.svc.cluster.local
   ```
3. Fais un `port-forward` et connecte-toi depuis ton PC (DBeaver, IntelliJ ou `psql` si installé) :
   ```powershell
   kubectl port-forward pod/postgres-0 5432:5432
   ```

**Questions**
- Quel nom ton application Spring Boot utiliserait-elle dans `spring.datasource.url` ?
- Quelle est la différence entre le nom `postgres` et `postgres-0.postgres...` ?

---

## Exercice 7 : Sauvegarde (bonus)

1. Exporte la base depuis le Pod. Attention : avec PowerShell 5, une redirection `>` écrit en UTF-16. Utilise plutôt :
   ```powershell
   kubectl exec postgres-0 -- pg_dump -U boutique_app boutique | Out-File -Encoding utf8 sauvegarde.sql
   ```
2. Ouvre `sauvegarde.sql` et repère tes `CREATE TABLE` et `INSERT` / `COPY`.
3. **Ne commite pas ce fichier** dans Git : ajoute `*.sql` à ton `.gitignore`.

**Questions**
- Pourquoi une sauvegarde reste-t-elle indispensable même avec un volume persistant ?
- Comment restaurerais-tu ce fichier dans une base vide ?

---

## Exercice 8 : Le piège de la réplication (bonus)

1. Passe à 2 réplicas : `kubectl scale statefulset postgres --replicas=2`.
2. Observe `kubectl get pods,pvc` : un `postgres-1` et un `data-postgres-1` apparaissent.
3. Connecte-toi à `postgres-1` et cherche ta table `clients`.
4. Repasse à 1 réplica, puis regarde `kubectl get pvc`.

**Questions**
- `postgres-1` contient-il tes données ? Pourquoi ?
- Qu'est-ce qu'un StatefulSet garantit, et qu'est-ce qu'il ne garantit **pas** ?
- Que devient le PVC `data-postgres-1` quand tu réduis les réplicas ? Pourquoi est-ce voulu ?

---

## Exercice 9 : Casser le stockage

**A. Mot de passe manquant**

Retire (en commentaire) l'entrée `POSTGRES_PASSWORD` du StatefulSet dans une copie du manifest, supprime le StatefulSet **et son PVC**, puis applique la copie. Observe le statut et les logs. Remets ensuite le manifest d'origine.

**B. Mauvais nom de Secret**

Mets `name: postgres-secrett` (avec deux `t`) dans `secretKeyRef`. Observe le statut du Pod.

**Questions**
- Quels statuts obtiens-tu dans chaque cas ?
- Dans quel ordre lis-tu `describe pod` et `logs` pour diagnostiquer ?

---

## Questions d'auto-évaluation

1. Pourquoi le disque d'un conteneur n'est-il pas adapté à une base de données ?
2. Quelle est la différence entre un PV, un PVC et une StorageClass ?
3. Qu'est-ce que le provisionnement dynamique ?
4. Pourquoi utilise-t-on un StatefulSet plutôt qu'un Deployment pour PostgreSQL ?
5. À quoi sert le Service headless associé à un StatefulSet ?
6. Quelle opération détruit les données, et lesquelles les conservent ?
7. Un StatefulSet de 3 réplicas PostgreSQL te donne-t-il une base répliquée ? Que faudrait-il utiliser ?
8. Que perds-tu avec `minikube delete` que tu conserves avec `minikube stop` ?

---

## Nettoyage (⚠️ supprime les données)

```powershell
kubectl delete statefulset postgres --ignore-not-found
kubectl delete pvc --all
kubectl delete -f manifests/postgres-service.yaml --ignore-not-found
kubectl delete -f manifests/postgres-secret.yaml --ignore-not-found
kubectl delete pod pvc-demo emptydir-demo --ignore-not-found
kubectl get pv,pvc
```