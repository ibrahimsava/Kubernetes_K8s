# Exercices - Module 02

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 **Connexion lente :** utilise `nginx:1.27` (déjà téléchargée) et `nginx:1.27-alpine` (environ 20 Mo) pour tes tests. Évite de multiplier les images différentes.

---

## Exercice 1 : Ton premier Deployment

1. Génère un manifest sans rien créer :
   ```bash
   kubectl create deployment api --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml > api.yaml
   ```
2. Ouvre `api.yaml`, repère `selector`, `template` et `replicas`.
3. Applique-le, puis liste les Deployments, ReplicaSets et Pods.

**Questions**
- Comment s'appelle le ReplicaSet créé ? Que représente le suffixe ?
- Comment s'appellent les Pods ? Que représentent les deux suffixes ?
- Quel label Kubernetes a-t-il ajouté automatiquement ?

---

## Exercice 2 : Auto-réparation

1. Suis les Pods avec `kubectl get pods -w` dans un terminal.
2. Dans un autre, supprime un Pod de `api`.
3. Supprime ensuite **tous** les Pods d'un coup : `kubectl delete pods -l app=api`.

**Questions**
- Combien de temps met Kubernetes à recréer les Pods ?
- Les nouveaux Pods ont-ils les mêmes noms et les mêmes IP que les anciens ?
- Qui est responsable de les recréer : le Deployment ou le ReplicaSet ?

---

## Exercice 3 : Scaling

1. Passe `api` à 6 réplicas avec `kubectl scale`.
2. Repasse à 2 en **modifiant le fichier** `api.yaml` puis `kubectl apply -f`.
3. Compare les deux méthodes. Laquelle laisse une trace dans Git ?

**Questions**
- Le scaling a-t-il créé un nouveau ReplicaSet ? Pourquoi ?
- Que se passe-t-il si tu scales à 0 ? Les ressources sont-elles supprimées ?

---

## Exercice 4 : Mise à jour progressive

1. Remets `api` à 4 réplicas et note l'image actuelle.
2. Dans un terminal : `kubectl get pods -w`.
3. Dans un autre :
   ```bash
   kubectl set image deployment/api nginx=nginx:1.27-alpine
   kubectl rollout status deployment/api
   ```
4. Après la fin, regarde `kubectl get rs` et `kubectl rollout history deployment/api`.

**Questions**
- Combien de Pods tournaient en même temps au maximum pendant la mise à jour ? Pourquoi ?
- Combien de ReplicaSets vois-tu maintenant ? Que contient l'ancien ?
- Quelle commande te permet de vérifier la version de nginx dans un Pod ?

---

## Exercice 5 : Régler la vitesse d'une mise à jour

Modifie `api.yaml` pour ajouter :

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 2
    maxUnavailable: 1
```

1. Applique-le, puis refais une mise à jour d'image (reviens à `nginx:1.27`).
2. Observe le comportement avec `kubectl get pods -w`.
3. Teste ensuite `type: Recreate` et compare.

**Questions**
- Quelle stratégie est la plus rapide ? La plus sûre ?
- Dans quel cas utiliserais-tu `Recreate` ?

---

## Exercice 6 : Mise à jour cassée et rollback 🔧

1. Provoque une mauvaise mise à jour :
   ```bash
   kubectl set image deployment/api nginx=nginx:version-inexistante
   ```
2. Observe `kubectl get pods` et `kubectl rollout status deployment/api`.
3. Trouve la cause avec `kubectl describe pod <nouveau-pod>` (Events).
4. Vérifie que l'application répond toujours (via `port-forward` sur un ancien Pod).
5. Reviens en arrière avec `kubectl rollout undo`.
6. Consulte `kubectl rollout history` : combien de révisions y a-t-il ?

**Questions**
- Pourquoi l'application a-t-elle continué à fonctionner pendant l'échec ?
- Que se serait-il passé avec `maxUnavailable: 100%` ?
- Un `rollout undo` supprime-t-il la révision cassée de l'historique ?

---

## Exercice 7 : Labels et selectors

1. Crée un Pod seul, avec le label `app: api` :
   ```bash
   kubectl run intrus --image=nginx:1.27 --labels="app=api"
   ```
2. Observe ce que fait le ReplicaSet de `api`.
3. Supprime le label du Pod `intrus` : `kubectl label pod intrus app-`.
4. Que se passe-t-il ?

**Questions**
- Pourquoi le Deployment a-t-il supprimé (ou adopté) un Pod qu'il n'avait pas créé ?
- Pourquoi ce comportement est-il à la fois utile et dangereux ?

---

## Exercice 8 : Job et CronJob (bonus)

1. Crée un Job qui s'exécute une fois :
   ```bash
   kubectl create job hello --image=busybox:1.36 -- echo "Bonjour Kubernetes"
   kubectl get jobs
   kubectl logs job/hello
   ```
2. Crée un CronJob qui s'exécute toutes les minutes :
   ```bash
   kubectl create cronjob chaque-minute --image=busybox:1.36 --schedule="* * * * *" -- date
   kubectl get cronjob
   kubectl get pods -w
   ```
3. Supprime-les ensuite.

**Questions**
- Quel est le statut d'un Pod de Job une fois terminé ?
- Pourquoi un Deployment ne convient-il pas pour ce genre de tâche ?

---

## Questions d'auto-évaluation

1. Pourquoi ne crée-t-on presque jamais de Pods directement ?
2. Quelle est la différence entre un ReplicaSet et un Deployment ?
3. Comment un Deployment retrouve-t-il ses Pods ?
4. Quelles modifications déclenchent un rollout, et lesquelles non ?
5. Que font `maxSurge` et `maxUnavailable` ?
6. Comment reviens-tu à la version précédente après une mauvaise mise à jour ?
7. Pour quel type d'application utilise-t-on un StatefulSet plutôt qu'un Deployment ?

---

## Nettoyage

```bash
kubectl delete deployment api web
kubectl delete pod intrus --ignore-not-found
kubectl delete job hello --ignore-not-found
kubectl delete cronjob chaque-minute --ignore-not-found
```