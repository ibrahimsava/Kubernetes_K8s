# Exercices - Module 08

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 Tout utilise `nginx:1.27`, déjà chez toi. L'exercice 3 propose un tag `1.27-alpine` (environ 20 Mo) : il est **optionnel** avec ta connexion lente.
>
> Commandes pour **PowerShell**, depuis le dossier du module.
>
> ⚠️ Avant d'appliquer, regarde toujours le rendu : `kubectl kustomize`, `kubectl diff -k` ou `helm template`.

---

## Exercice 1 : Lire un rendu Kustomize

1. Affiche les trois rendus :
   ```powershell
   kubectl kustomize kustomize/base
   kubectl kustomize kustomize/overlays/dev
   kubectl kustomize kustomize/overlays/test
   ```
2. Note les différences entre `dev` et `test` : namespace, réplicas, labels, nom du ConfigMap, ressources.
3. Applique l'overlay `dev` : `kubectl apply -k kustomize/overlays/dev`.

**Questions**
- Pourquoi le nom du ConfigMap contient-il un suffixe aléatoire ?
- Dans le Deployment, la référence au ConfigMap pointe-t-elle vers `app-config` ou vers le nom avec hash ? Qui l'a modifiée ?
- La base seule peut-elle être appliquée telle quelle ? Pourquoi ?

---

## Exercice 2 : Créer un overlay `prod` 🔧

Crée `kustomize/overlays/prod/` avec :

- un `namespace.yaml` pour `prod`
- un `kustomization.yaml` qui :
  - place tout dans le namespace `prod`
  - passe à **5 réplicas**
  - ajoute le label `env: prod` (sans toucher aux selectors)
  - génère un ConfigMap avec `APP_ENV=prod` et `LOG_LEVEL=warn`
- un `patch-resources.yaml` qui porte les ressources à `requests: 250m / 256Mi` et `limits: 500m / 512Mi`

Vérifie avec `kubectl kustomize`, puis applique-le **seulement si ton cluster a assez de ressources** (5 réplicas en plus des autres namespaces). Sinon, contente-toi du rendu.

**Questions**
- Quels fichiers de `base/` as-tu dû modifier ? (La bonne réponse est : aucun.)
- Comment ajouterais-tu un quatrième environnement en moins de 5 minutes ?

---

## Exercice 3 : Changer l'image et ajouter une annotation

1. Dans l'overlay `test`, ajoute :
   ```yaml
   commonAnnotations:
     equipe: "web"
   images:
     - name: nginx
       newTag: "1.27"
   ```
2. Affiche le rendu et retrouve l'annotation sur toutes les ressources.
3. *(Optionnel)* Remplace `newTag` par `"1.27-alpine"`, applique, et observe le redéploiement.

**Questions**
- Pourquoi la transformation `images` est-elle pratique dans un pipeline CI/CD ?
- Quelle différence entre `commonAnnotations` et `labels` ?

---

## Exercice 4 : Un patch JSON 6902

Dans l'overlay `dev`, ajoute un patch JSON qui **ajoute une variable d'environnement** `FEATURE_X=on` au conteneur `nginx` :

```yaml
patches:
  - target:
      kind: Deployment
      name: web
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env
        value:
          - name: FEATURE_X
            value: "on"
```

Affiche le rendu, applique, puis vérifie : `kubectl exec deploy/web -n dev -- env`.

**Questions**
- Que signifie le `/0/` dans le chemin ?
- Quand choisir un patch JSON 6902 plutôt qu'un strategic merge ?

---

## Exercice 5 : Config qui change, Pods qui suivent

1. Modifie une valeur de `configMapGenerator` dans `dev`.
2. Lance `kubectl diff -k kustomize/overlays/dev`, puis `kubectl apply -k kustomize/overlays/dev`.
3. Liste les ConfigMaps et les Pods : `kubectl get cm,pods -n dev`.

**Questions**
- Comparé au module 04, qu'est-ce qui te dispense de faire `kubectl rollout restart` ?
- Que deviennent les anciens ConfigMaps ? Comment les nettoyer ?

Nettoyage : `kubectl delete -k kustomize/overlays/dev` et `kubectl delete -k kustomize/overlays/test`.

---

## Exercice 6 : Explorer un chart généré

1. Installe Helm (voir le cours, section 6) et vérifie `helm version`.
2. Génère un chart d'exemple :
   ```powershell
   helm create demo
   ```
3. Explore le dossier `demo/` : `Chart.yaml`, `values.yaml`, `templates/`.
4. Lance `helm lint demo` et `helm template demo-test demo`.
5. **Ne l'installe pas** (son image par défaut est la même que la nôtre, mais ce n'est pas l'objet de l'exercice).

**Questions**
- Quelle image utilise le chart par défaut ? Où est-elle définie ?
- Que contient `_helpers.tpl` ? À quoi servent les fonctions qui y sont définies ?
- Quelles ressources le chart crée-t-il quand tu ne changes aucune valeur ? Lesquelles sont conditionnelles ?

Nettoyage : supprime le dossier `demo`.

---

## Exercice 7 : Valeurs et priorité

Avec le chart `helm/boutique-web`, prédis puis vérifie avec `helm template` le nombre de réplicas dans chaque cas :

| Commande | Réplicas attendus |
|----------|-------------------|
| `helm template w helm/boutique-web` | ? |
| `... -f helm/boutique-web/values-dev.yaml` | ? |
| `... -f helm/boutique-web/values-test.yaml` | ? |
| `... -f helm/boutique-web/values-test.yaml --set replicaCount=7` | ? |
| `... -f helm/boutique-web/values-dev.yaml -f helm/boutique-web/values-test.yaml` | ? |

**Questions**
- Dans quel ordre les sources de valeurs sont-elles appliquées ?
- Quand deux fichiers `-f` définissent la même valeur, lequel gagne ?
- Comment modifier le tag de l'image sans toucher au fichier de valeurs ?

---

## Exercice 8 : Modifier un chart 🔧

Dans une copie du chart (`helm/mon-chart`, renomme aussi `name:` dans `Chart.yaml` et les noms de templates dans `_helpers.tpl`), ajoute :

1. une valeur `service.type` déjà présente : change-la en `NodePort` dans un fichier de valeurs et vérifie le rendu
2. une nouvelle valeur `replicaCount` obligatoire avec la fonction `required` (le rendu doit échouer si elle est vide)
3. une annotation `description` sur le Deployment, alimentée par une nouvelle valeur `description`
4. un bloc **conditionnel** qui n'ajoute une `env` supplémentaire que si `debug: true`

Vérifie chaque ajout avec `helm lint` et `helm template`.

**Questions**
- À quoi sert le `-` dans `{{-` ?
- Que se passe-t-il si tu oublies `nindent` après un `toYaml` ?

---

## Exercice 9 : Le cycle de vie d'une release

1. Installe le chart deux fois (`web-dev` dans `helm-dev` et `web-test` dans `helm-test`, avec leurs fichiers de valeurs).
2. Affiche `helm list -A` et les Secrets de `helm-dev`.
3. Mets `web-dev` à jour avec `--set replicaCount=3`, puis `--set config.LOG_LEVEL=error`.
4. Affiche `helm history web-dev -n helm-dev` et `helm get values web-dev -n helm-dev`.
5. Reviens à la révision 1 avec `helm rollback`, et vérifie le nombre de réplicas.
6. Provoque une mise à jour cassée (`--set image.tag=nexiste-pas`) **avec** puis **sans** `--wait --timeout 60s`.

**Questions**
- Pourquoi un `rollback` crée-t-il une **nouvelle** révision plutôt que de supprimer les suivantes ?
- Où Helm stocke-t-il l'historique des révisions ?
- Que change `--wait` dans le comportement de `helm upgrade` ?
- Que se passe-t-il pour les Pods quand tu modifies `config.LOG_LEVEL` ? Quel mécanisme du chart en est responsable ?

Nettoyage : `helm uninstall` des deux releases, puis `kubectl delete namespace helm-dev helm-test`.

---

## Exercice 10 : Choisir l'outil

Pour chaque situation, indique **Helm**, **Kustomize** ou **les deux**, et justifie en une phrase :

1. Installer PostgreSQL en haute disponibilité avec un chart communautaire.
2. Déployer ton API Spring Boot sur trois environnements, avec des réplicas et des variables différents.
3. Livrer ton application à un client qui veut la configurer avec 20 options.
4. Un pipeline CI/CD qui met à jour uniquement le tag de l'image.
5. Installer l'Ingress Controller et ton application, dans le même pipeline.

---

## Questions d'auto-évaluation

1. Pourquoi ne faut-il pas copier les fichiers YAML pour chaque environnement ?
2. Qu'est-ce qu'une base et un overlay dans Kustomize ?
3. Que fait `kubectl kustomize` par rapport à `kubectl apply -k` ?
4. Quelle est la différence entre un chart, une release et une revision ?
5. Dans quel ordre Helm applique-t-il `values.yaml`, `-f` et `--set` ?
6. Comment Helm peut-il faire un rollback ? Où est stocké l'historique ?
7. Pourquoi une release peut-elle être `deployed` alors que l'application est cassée ?
8. Comment les deux outils redéploient-ils les Pods quand un ConfigMap change ?
9. Quand préfères-tu Helm, et quand Kustomize ?

---

## Nettoyage

```powershell
kubectl delete -k kustomize/overlays/dev --ignore-not-found
kubectl delete -k kustomize/overlays/test --ignore-not-found
helm uninstall web-dev -n helm-dev
helm uninstall web-test -n helm-test
kubectl delete namespace helm-dev helm-test --ignore-not-found
kubectl get ns
```
