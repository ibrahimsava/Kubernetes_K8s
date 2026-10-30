# Exercices - Module 06

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 Les exercices 1 à 7 n'utilisent que `nginx:1.27` et `busybox:1.36`, déjà chez toi. Seul l'exercice 8 (autoscaling) nécessite le **metrics-server** (petit téléchargement depuis `registry.k8s.io`).
>
> Commandes pour **PowerShell**. Utilise des guillemets **simples** autour des expressions contenant `$` ou `{}`.

---

## Exercice 1 : Lire les probes d'un Deployment

1. Applique `manifests/deployment-probes.yaml`.
2. Lance `kubectl describe pod -l app=web-sante` et repère les lignes `Liveness`, `Readiness`, `Limits`, `Requests` et `QoS Class`.
3. Calcule : avec `periodSeconds: 5` et `failureThreshold: 3`, au bout de combien de temps Kubernetes considère-t-il un Pod non prêt ?

**Questions**
- Pourquoi la `livenessProbe` a-t-elle un `initialDelaySeconds` plus grand que la `readinessProbe` ?
- Dans quelle classe de QoS est ce Pod, et pourquoi ?

---

## Exercice 2 : La readiness retire un Pod du Service 🔧

1. Dans un terminal : `kubectl get pods -w`.
2. Dans un autre, applique `manifests/deployment-readiness-cassee.yaml`.
3. Observe la colonne `READY` des nouveaux Pods.
4. Affiche les Endpoints du Service : `kubectl get endpointslices -l kubernetes.io/service-name=web-sante`.
5. Teste le Service depuis un Pod temporaire :
   ```powershell
   kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web-sante
   ```
6. Reviens en arrière avec `kubectl rollout undo deployment/web-sante`.

**Questions**
- Les nouveaux Pods sont-ils redémarrés ? Pourquoi (ou pourquoi pas) ?
- Le Service répond-il toujours ? De quels Pods viennent les réponses ?
- Quel est le lien avec `maxUnavailable: 0` du module 02 ?
- Quel message exact vois-tu dans les Events ?

---

## Exercice 3 : La liveness redémarre un conteneur

1. Applique `manifests/pod-liveness.yaml` et suis `kubectl get pod liveness-demo -w`.
2. Note le moment où `RESTARTS` passe à 1.
3. Lis les Events avec `kubectl describe pod liveness-demo`.
4. Après le redémarrage, le fichier `/tmp/healthy` existe-t-il à nouveau ?  
   `kubectl exec liveness-demo -- ls /tmp`

**Questions**
- Combien de temps s'écoule entre la disparition du fichier et le redémarrage ? Retrouve ce délai avec `periodSeconds` et `failureThreshold`.
- Pourquoi le fichier existe-t-il de nouveau après le redémarrage ?
- Quelle commande te montre les logs du conteneur **avant** son redémarrage ?

---

## Exercice 4 : Différencier les trois probes

Pour chaque situation, indique **quelle probe** (readiness, liveness ou startup) tu utiliserais, et pourquoi :

1. Une API Spring Boot qui met 90 secondes à démarrer.
2. Une application qui, parfois, se bloque complètement sans planter.
3. Une API qui perd temporairement sa connexion à la base de données.
4. Une application qui doit charger un gros cache avant de répondre.
5. Un Pod à retirer du trafic pendant une maintenance, sans le redémarrer.

**Question piège :** pourquoi est-ce une mauvaise idée de faire dépendre la **liveness** de la base de données ?

---

## Exercice 5 : Les trois classes de QoS

Crée trois Pods avec `kubectl apply` (écris les manifests toi-même) :

| Pod | Ressources |
|-----|-----------|
| `qos-guaranteed` | `requests` = `limits` pour CPU et mémoire |
| `qos-burstable` | `requests` plus bas que les `limits` |
| `qos-besteffort` | aucune ressource déclarée |

Utilise `nginx:1.27` pour les trois, puis :

```powershell
kubectl get pod qos-guaranteed -o jsonpath='{.status.qosClass}'
kubectl get pod qos-burstable -o jsonpath='{.status.qosClass}'
kubectl get pod qos-besteffort -o jsonpath='{.status.qosClass}'
```

**Questions**
- Les trois classes obtenues correspondent-elles à tes attentes ?
- Que se passe-t-il si tu définis des `requests` mais **pas** de `limits` ?
- Quel Pod serait évincé en premier en cas de manque de mémoire sur le nœud ?

---

## Exercice 6 : OOMKilled 🔧

1. Applique `manifests/pod-oom.yaml` et observe `kubectl get pod oom-demo -w`.
2. Lis `kubectl describe pod oom-demo` : cherche `Last State`, `Reason` et `Exit Code`.
3. Modifie la limite mémoire de 50Mi à 300Mi dans une copie du fichier, supprime l'ancien Pod, applique la copie. Que se passe-t-il ?

**Questions**
- Que signifie le code de sortie `137` ?
- Pourquoi la mémoire fait-elle **tuer** le conteneur alors que le CPU ne fait que le **ralentir** ?
- Pour une API Java, pourquoi la limite mémoire doit-elle être **supérieure** au heap de la JVM ?

---

## Exercice 7 : Pod Pending

1. Applique `manifests/pod-trop-gros.yaml`.
2. Trouve la raison exacte dans `kubectl describe pod trop-gros` (section Events).
3. Affiche la capacité du nœud : `kubectl describe node minikube` (sections `Capacity` et `Allocated resources`).
4. Corrige le manifest avec des valeurs réalistes (par exemple `cpu: 100m`, `memory: 128Mi`) et vérifie que le Pod démarre.

**Questions**
- Pourquoi le Pod n'est-il ni en `Error` ni en `CrashLoopBackOff` ?
- Qui prend la décision de ne pas démarrer le Pod : le scheduler ou le kubelet ?
- Combien de `requests` CPU sont déjà allouées sur ton nœud ?

---

## Exercice 8 : Autoscaling (optionnel)

1. Installe le metrics-server : `minikube addons enable metrics-server`, puis attends `kubectl top nodes`.
2. Applique `manifests/deployment-hpa.yaml` et `manifests/hpa.yaml`.
3. Dans un terminal : `kubectl get hpa -w`.
4. Dans un autre, lance 3 générateurs de charge (voir le TP, étape 7c).
5. Observe la colonne `TARGETS` et `REPLICAS`, puis supprime la charge et observe la descente.

**Questions**
- Pourquoi le HPA a-t-il besoin que les Pods aient des `requests` ?
- Avec 2 Pods à 100 % de CPU et une cible de 50 %, combien de Pods le HPA demande-t-il ? (Utilise la formule du cours.)
- Pourquoi la descente est-elle plus lente que la montée ?
- Que se passe-t-il si tu enlèves la `request` CPU du Deployment ?

**Bonus :** passe `maxReplicas` à 2 et observe : quelle limite le HPA respecte-t-il ?

---

## Exercice 9 : Configurer une API Spring Boot

Sans copier `spring-boot-probes.yaml`, écris la partie `containers` d'un Deployment pour une API Spring Boot qui :

- écoute sur le port `8080`
- met jusqu'à 2 minutes à démarrer
- expose `/actuator/health/liveness` et `/actuator/health/readiness`
- a besoin d'environ 512 Mi de mémoire et d'un quart de cœur CPU
- ne doit pas dépasser 1 Gi de mémoire

Compare ensuite avec `manifests/spring-boot-probes.yaml`.

**Questions**
- Quelle probe protège l'application pendant son démarrage ?
- Quelle valeur de `failureThreshold` donne 2 minutes avec `periodSeconds: 5` ?
- Comment la JVM sait-elle quelle quantité de mémoire utiliser ?

---

## Questions d'auto-évaluation

1. Quelle est la différence entre une readiness et une liveness probe ?
2. Que fait Kubernetes quand une readiness probe échoue ? Et une liveness ?
3. À quoi sert une startup probe ?
4. Quelle est la différence entre `requests` et `limits` ?
5. Que se passe-t-il quand un conteneur dépasse sa limite de CPU ? De mémoire ?
6. Qu'est-ce qu'un Pod `Pending` avec `Insufficient memory` ?
7. Quels sont les trois prérequis d'un HPA qui fonctionne ?
8. Pourquoi ne faut-il jamais faire dépendre la liveness d'une base de données ?

---

## Nettoyage

```powershell
kubectl delete hpa web-hpa --ignore-not-found
kubectl delete deployment web-hpa web-sante --ignore-not-found
kubectl delete svc web-hpa web-sante --ignore-not-found
kubectl delete pod liveness-demo oom-demo trop-gros charge1 charge2 charge3 qos-guaranteed qos-burstable qos-besteffort tmp --ignore-not-found
```