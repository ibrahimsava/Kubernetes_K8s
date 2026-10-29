# Exercices - Module 04

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 Toutes les images utilisées (`nginx:1.27`, `busybox:1.36`) sont déjà chez toi : pas de téléchargement lourd.
>
> Commandes pour **PowerShell**. Utilise des guillemets **simples** autour des expressions contenant `$` ou `{}`.
>
> 🔒 **Rappel :** n'utilise que de **fausses** valeurs dans ces exercices, et ne commite jamais de vrais secrets sur GitHub.

---

## Exercice 1 : Trois façons de créer un ConfigMap

1. **Par commande :**
   ```powershell
   kubectl create configmap cfg-litteral --from-literal=COULEUR=bleu --from-literal=LANGUE=fr
   ```
2. **Depuis un fichier :** crée un fichier `app.properties` contenant :
   ```
   server.port=8080
   app.mode=demo
   ```
   puis :
   ```powershell
   kubectl create configmap cfg-fichier --from-file=app.properties
   ```
3. **Depuis un manifest :** écris toi-même un ConfigMap `cfg-yaml` avec deux clés de ton choix, puis `kubectl apply -f`.
4. Compare les trois avec `kubectl get configmap <nom> -o yaml`.

**Questions**
- Quelle est la clé créée par `--from-file` ? Et sa valeur ?
- Quelle méthode préfères-tu pour un vrai projet, et pourquoi ?

---

## Exercice 2 : Un Secret n'est pas un coffre-fort

1. Crée un Secret :
   ```powershell
   kubectl create secret generic mon-secret --from-literal=TOKEN=abc123-fictif
   ```
2. Affiche-le : `kubectl get secret mon-secret -o yaml`.
3. Décode la valeur avec PowerShell :
   ```powershell
   [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("<valeur>"))
   ```
4. Compare avec `kubectl describe secret mon-secret`.

**Questions**
- Que montre `describe` par rapport à `get -o yaml` ?
- Pourquoi dit-on que base64 n'est pas du chiffrement ?
- Si tu commites ce Secret dans un repo public, que se passe-t-il ?

**Bonus :** écris le même Secret avec `stringData` puis avec `data` (tu dois encoder toi-même). Applique les deux et vérifie qu'ils donnent le même résultat.

---

## Exercice 3 : Variables d'environnement

1. Applique `manifests/configmap.yaml`, `manifests/secret.yaml` puis `manifests/pod-env.yaml`.
2. Lis les logs du Pod : `kubectl logs env-demo`.
3. Modifie `pod-env.yaml` pour **renommer** la variable `DB_USER` en `UTILISATEUR_BASE` (indice : c'est le champ `name` dans `env`, pas la `key`).
4. Supprime le Pod, réapplique et vérifie.

**Questions**
- Quelle différence entre `envFrom` et `env` + `valueFrom` ?
- Pourquoi peut-on lire le mot de passe avec `kubectl exec env-demo -- env` ? Qu'est-ce que cela implique pour la sécurité ?

---

## Exercice 4 : Fichiers montés

1. Applique `manifests/deployment-config.yaml`.
2. Liste le contenu de `/usr/share/nginx/html` et de `/etc/secrets` dans un Pod.
3. Affiche le contenu de `/etc/secrets/DB_PASSWORD`.
4. Affiche la page avec `kubectl port-forward deployment/web-config 8080:80`.

**Questions**
- Combien de fichiers vois-tu dans `/etc/secrets` ? Pourquoi ce nombre ?
- Le montage du ConfigMap sur `/usr/share/nginx/html` a-t-il remplacé la page par défaut de Nginx ? Pourquoi ?

---

## Exercice 5 : Mise à jour à chaud 🔧

1. Dans `configmap.yaml`, change `Configuration v1` en `Configuration v2` et `APP_ENV: "dev"` en `APP_ENV: "prod"`.
2. Applique, **n'attends pas**, et vérifie immédiatement le fichier et la variable.
3. Attends 1 à 2 minutes et recompare :
   ```powershell
   kubectl exec deploy/web-config -- cat /usr/share/nginx/html/index.html
   kubectl exec deploy/web-config -- env
   ```
4. Fais `kubectl rollout restart deployment/web-config` et recompare une dernière fois.

**Questions**
- Dans quel ordre les trois éléments se sont-ils mis à jour : fichier monté, variable, après redémarrage ?
- Pourquoi les variables d'environnement ne peuvent-elles pas changer dans un processus déjà lancé ?
- Si ton application Spring Boot lit sa configuration au démarrage, que dois-tu faire après un changement de ConfigMap ?

---

## Exercice 6 : Casser la configuration

**A. ConfigMap inexistant**

Crée un Pod qui référence un ConfigMap qui n'existe pas :

```powershell
kubectl run casse --image=busybox:1.36 --restart=Never --overrides='{"spec":{"containers":[{"name":"casse","image":"busybox:1.36","command":["sleep","3600"],"envFrom":[{"configMapRef":{"name":"nexiste-pas"}}]}]}}'
```

1. Quel est le statut du Pod ?
2. Trouve la cause avec `kubectl describe pod casse`.
3. Corrige en créant le ConfigMap manquant : `kubectl create configmap nexiste-pas --from-literal=A=1`. Que se passe-t-il ?

**B. Clé inexistante**

Dans une copie de `pod-env.yaml`, remplace `key: DB_PASSWORD` par `key: MOT_DE_PASSE`. Applique et observe le statut.

**C. Ressource facultative**

Ajoute `optional: true` sous le `configMapRef` ou le `secretKeyRef` d'un cas cassé. Que change ce champ ?

**Questions**
- Quel statut apparaît pour une configuration introuvable ?
- Dans quel cas `optional: true` est-il utile, et dans quel cas est-il dangereux ?

---

## Exercice 7 : Une vraie configuration Spring Boot

Sans copier `spring-boot-exemple.yaml`, écris les manifests pour une application dont les propriétés sont :

```
spring.datasource.url=jdbc:postgresql://postgres:5432/boutique
spring.datasource.username=boutique_app
spring.datasource.password=<secret>
spring.profiles.active=prod
logging.level.root=INFO
```

1. Écris les noms des variables d'environnement équivalentes.
2. Sépare ce qui va dans un **ConfigMap** et ce qui va dans un **Secret**.
3. Écris le `Deployment` qui les injecte avec `envFrom`.
4. Compare avec `manifests/spring-boot-exemple.yaml`.

**Questions**
- Pourquoi l'hôte est-il `postgres` et pas une adresse IP ?
- Comment adapterais-tu la configuration pour un environnement de test différent de la production, sans toucher à l'image ?

---

## Exercice 8 : ConfigMap immuable (bonus)

1. Crée un ConfigMap avec `immutable: true` :
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: figee
   immutable: true
   data:
     VERSION: "1"
   ```
2. Essaie de modifier `VERSION` puis de réappliquer.

**Questions**
- Quel message d'erreur obtiens-tu ?
- Quel est l'intérêt d'un ConfigMap immuable (sécurité, performance, prévisibilité) ?
- Comment faire un changement malgré tout ?

---

## Questions d'auto-évaluation

1. Pourquoi sépare-t-on la configuration de l'image Docker ?
2. Quand utilises-tu un ConfigMap, et quand un Secret ?
3. Un Secret est-il chiffré par défaut ? Qu'est-ce qui le protège réellement ?
4. Quelle est la différence entre `data` et `stringData` dans un Secret ?
5. Quelle différence de mise à jour entre une variable d'environnement et un fichier monté ?
6. Que signifie un Pod en `CreateContainerConfigError` ?
7. Comment éviter de publier un secret par erreur sur GitHub ?

---

## Nettoyage

```powershell
kubectl delete pod env-demo casse --ignore-not-found
kubectl delete deployment web-config --ignore-not-found
kubectl delete configmap app-config page-config cfg-litteral cfg-fichier cfg-yaml nexiste-pas figee --ignore-not-found
kubectl delete secret db-secret mon-secret --ignore-not-found
```