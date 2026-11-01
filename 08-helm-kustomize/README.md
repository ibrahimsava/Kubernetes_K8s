# 08 - Helm et Kustomize : packaging et environnements

> **Objectif du module :** arrêter de copier-coller tes fichiers YAML pour chaque environnement, et apprendre à les paramétrer, les empaqueter et les versionner.

**Durée estimée :** 4 heures · **Prérequis :** modules 01 à 07 terminés, cluster Minikube démarré

---

## 1. Le problème

Ton application tourne en dev, en test et bientôt en production. Les fichiers sont presque identiques, mais quelques valeurs changent :

| Valeur | dev | test | prod |
|--------|-----|------|------|
| Réplicas | 1 | 3 | 5 |
| Ressources | petites | moyennes | grandes |
| `LOG_LEVEL` | debug | info | warn |
| Namespace | dev | test | prod |

Deux mauvaises solutions s'offrent à toi :

- **Copier les fichiers** pour chaque environnement : tu te retrouves avec trois jeux de YAML qui divergent peu à peu, et une correction à faire trois fois.
- **Modifier les fichiers à la main** avant chaque déploiement : source d'erreurs, impossible à automatiser.

Il faut **un seul modèle** et **des différences minimales** par environnement. Deux outils répondent à ce besoin.

---

## 2. Kustomize et Helm : deux philosophies

| | **Kustomize** | **Helm** |
|---|---------------|----------|
| Principe | On **superpose des modifications** (patches) à des YAML valides | On **écrit des templates** avec des variables |
| Les fichiers sont-ils du YAML valide ? | ✅ Oui, toujours | ❌ Non, ce sont des templates |
| Installation | **Déjà dans `kubectl`** (`kubectl apply -k`) | Un programme à installer (`helm`) |
| Gestion de versions et rollback | ❌ Non (il reste `kubectl`) | ✅ Oui, par **release** |
| Réutilisation à grande échelle | Limitée | ✅ **Charts** partageables, dépôts publics |
| Courbe d'apprentissage | Douce | Plus raide (templates Go) |
| Cas typique | Gérer **tes propres** applications entre environnements | **Installer des logiciels tiers** (PostgreSQL, Prometheus, Ingress) et packager ses applications |

> Ils ne s'excluent pas : beaucoup d'équipes **utilisent les deux**, par exemple Helm pour les logiciels tiers et Kustomize pour leurs propres applications.

---

## 3. Kustomize

### Le principe : base et overlays

```
kustomize/
├── base/                    ← le modèle commun
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/                ← les différences par environnement
    ├── dev/
    │   └── kustomization.yaml
    └── test/
        ├── kustomization.yaml
        └── patch-resources.yaml
```

Chaque overlay **part de la base** et y applique ses modifications. La base reste intacte et valide.

### Le fichier `kustomization.yaml`

Il décrit **quelles ressources** inclure et **quelles transformations** appliquer. Fichier [`kustomize/overlays/dev/kustomization.yaml`](./kustomize/overlays/dev/kustomization.yaml) :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev                 # toutes les ressources vont dans ce namespace

resources:
  - ../../base                 # on part de la base commune
  - namespace.yaml

replicas:
  - name: web                  # le Deployment à modifier
    count: 1

labels:
  - pairs:
      env: dev
    includeSelectors: false    # ne touche pas aux selectors (immuables)
    includeTemplates: true     # ajoute le label aux Pods

configMapGenerator:
  - name: app-config
    literals:
      - APP_ENV=dev
      - LOG_LEVEL=debug
```

### Les transformations les plus utiles

| Champ | Effet |
|-------|-------|
| `namespace` | Place toutes les ressources dans un namespace |
| `namePrefix` / `nameSuffix` | Ajoute un préfixe ou suffixe aux noms |
| `labels` | Ajoute des labels (avec `includeSelectors: false` pour ne pas toucher aux selectors) |
| `commonAnnotations` | Ajoute des annotations à tout |
| `images` | Change le nom ou le tag d'une image sans toucher au Deployment |
| `replicas` | Change le nombre de réplicas |
| `configMapGenerator` / `secretGenerator` | Génère des ConfigMaps et Secrets depuis des valeurs ou fichiers |
| `patches` | Modifie n'importe quel champ |

### Changer l'image sans modifier le Deployment

```yaml
images:
  - name: nginx
    newTag: "1.27-alpine"
```

Très utile en CI/CD : le pipeline met simplement à jour le tag de l'image.

### Les patches

Un **patch** modifie une partie d'une ressource. Le plus simple est le **strategic merge** : tu écris uniquement ce qui change. Fichier [`kustomize/overlays/test/patch-resources.yaml`](./kustomize/overlays/test/patch-resources.yaml) :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  template:
    spec:
      containers:
        - name: nginx          # identifie le conteneur à modifier
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
```

On l'active dans `kustomization.yaml` :

```yaml
patches:
  - path: patch-resources.yaml
```

Il existe aussi les patches **JSON 6902**, plus précis (ajouter, remplacer, supprimer un chemin exact) :

```yaml
patches:
  - target:
      kind: Deployment
      name: web
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
```

### Le `configMapGenerator` et son hash

Kustomize ajoute un **hash** au nom du ConfigMap généré (`app-config-h588hdc8kc`) et met à jour automatiquement les références dans les Deployments. Quand le contenu change, le nom change, donc le Deployment change, donc **les Pods sont redéployés**. Ça règle le piège du module 04 (« changer un ConfigMap ne redémarre pas les Pods »).

### Les commandes

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl kustomize <dossier>` | **Affiche** le YAML final, sans rien appliquer |
| `kubectl apply -k <dossier>` | Applique le résultat |
| `kubectl diff -k <dossier>` | Montre ce qui **changerait** dans le cluster |
| `kubectl delete -k <dossier>` | Supprime tout ce que le dossier définit |

> 💡 Prends l'habitude de lancer `kubectl kustomize` avant `apply -k` : tu vois exactement ce qui va être déployé.

---

## 4. Helm

### Les concepts

| Terme | Signification |
|-------|---------------|
| **Chart** | Un **paquet** : l'ensemble des templates et valeurs d'une application |
| **Values** | Les **paramètres** du chart (`values.yaml`) |
| **Release** | Une **installation** d'un chart dans un cluster, avec un nom |
| **Revision** | Chaque **version** d'une release (1, 2, 3...) |
| **Repository** | Un catalogue de charts partagés |

Un même chart peut être installé plusieurs fois, sous des noms différents : `web-dev`, `web-test`.

### Structure d'un chart

```
boutique-web/
├── Chart.yaml            ← identité du chart (nom, version)
├── values.yaml           ← valeurs par défaut
├── values-dev.yaml       ← surcharges pour dev
├── values-test.yaml      ← surcharges pour test
└── templates/
    ├── _helpers.tpl      ← fonctions réutilisables
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml
    ├── ingress.yaml
    └── NOTES.txt         ← message affiché après l'installation
```

Le chart de ce module est dans [`helm/boutique-web/`](./helm/boutique-web).

### Chart.yaml

```yaml
apiVersion: v2
name: boutique-web
description: Frontend Nginx de la boutique
type: application
version: 0.1.0          # version du CHART
appVersion: "1.27"      # version de l'APPLICATION
```

`version` change quand tu modifies le chart. `appVersion` indique la version du logiciel déployé.

### Les templates

Un template est un fichier YAML avec des **expressions entre `{{ }}`** remplacées au moment du rendu :

```yaml
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

### Les objets disponibles

| Objet | Contenu | Exemple |
|-------|---------|---------|
| `.Values` | Les valeurs du chart | `.Values.replicaCount` |
| `.Release` | Infos sur la release | `.Release.Name`, `.Release.Namespace` |
| `.Chart` | Contenu de `Chart.yaml` | `.Chart.Name`, `.Chart.AppVersion` |

### Les constructions courantes

| Construction | Rôle | Exemple |
|--------------|------|---------|
| `default` | Valeur par défaut | `{{ .Values.tag \| default .Chart.AppVersion }}` |
| `quote` | Met entre guillemets | `{{ .Values.nom \| quote }}` |
| `if` | Condition | `{{- if .Values.ingress.enabled }} ... {{- end }}` |
| `range` | Boucle | `{{- range $cle, $val := .Values.config }}` |
| `toYaml` | Convertit un bloc en YAML | `{{- toYaml .Values.resources \| nindent 12 }}` |
| `include` | Appelle un template nommé | `{{ include "boutique-web.fullname" . }}` |
| `required` | Erreur si la valeur manque | `{{ required "image obligatoire" .Values.image.repository }}` |

### Le contrôle des espaces

Le tiret dans `{{-` et `-}}` supprime les espaces et sauts de ligne autour. `nindent 4` ajoute un saut de ligne puis 4 espaces : indispensable pour que le YAML reste bien indenté. Une erreur d'indentation est le problème le plus fréquent avec Helm.

### Le hash de configuration

Dans notre `deployment.yaml` :

```yaml
annotations:
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

Si le ConfigMap change, ce hash change, donc le template du Pod change, donc **Helm redéploie les Pods**. C'est l'équivalent Helm du hash de Kustomize.

### Surcharger les valeurs

L'ordre de priorité, du plus faible au plus fort :

```
values.yaml du chart  <  -f fichier.yaml (dans l'ordre)  <  --set cle=valeur
```

```bash
helm install web-dev ./boutique-web -f values-dev.yaml
helm install web-dev ./boutique-web -f values-dev.yaml --set replicaCount=2
```

### Le cycle de vie d'une release

```bash
helm install web-dev ./boutique-web -n dev --create-namespace   # installer
helm upgrade web-dev ./boutique-web -n dev --set replicaCount=3 # mettre à jour
helm history web-dev -n dev                                     # voir les révisions
helm rollback web-dev 1 -n dev                                  # revenir à la révision 1
helm uninstall web-dev -n dev                                   # supprimer
```

Helm garde **l'historique de chaque révision** dans des **Secrets** du namespace (`sh.helm.release.v1.web-dev.v1`, `...v2`). C'est ce qui lui permet de faire un rollback.

### Helm ne sait pas si ton application va bien

Par défaut, Helm déclare une release `deployed` dès que les ressources sont **créées**, pas quand les Pods sont **prêts**. Si l'image est introuvable, la release est « réussie » alors que l'application est cassée. Pour que Helm attende et signale l'échec :

```bash
helm upgrade --install web-dev ./boutique-web -n dev --wait --timeout 2m
```

On peut aussi lui demander de revenir automatiquement en arrière en cas d'échec. Cette option s'appelle `--atomic` dans Helm 3 et a été renommée `--rollback-on-failure` dans Helm 4 : vérifie avec `helm upgrade --help` selon ta version.

### Les commandes de diagnostic (à connaître)

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `helm lint <chart>` | Vérifie la syntaxe et les bonnes pratiques |
| `helm template <nom> <chart> -f values.yaml` | **Affiche** le YAML généré, sans rien installer |
| `helm install ... --dry-run --debug` | Simule une installation |
| `helm get values <release>` | Valeurs utilisées par une release |
| `helm get manifest <release>` | YAML réellement déployé |
| `helm status <release>` | État de la release |

### Dépôts et dépendances

Des milliers de charts sont partagés dans des dépôts publics :

```bash
helm repo add <nom> <url>
helm repo update
helm search repo <mot-clé>
helm install ma-base <nom>/<chart>
```

Un chart peut aussi dépendre d'autres charts (déclarés dans `Chart.yaml`, installés avec `helm dependency update`). Ce module n'utilise **aucun chart distant** : ils téléchargent des images lourdes, ce qui est pénible avec ta connexion. Tu le feras plus tard, quand tu auras un meilleur réseau.

### Helm 3 ou Helm 4 ?

Les commandes de ce module fonctionnent avec les deux. Helm 4 a renommé quelques options avancées (comme `--atomic`). Si une option est refusée, consulte `helm <commande> --help`.

---

## 5. Lequel choisir ?

| Situation | Choix conseillé |
|-----------|-----------------|
| Installer PostgreSQL, Prometheus, un Ingress Controller | **Helm** (charts existants) |
| Déployer ta propre API sur dev/test/prod avec quelques différences | **Kustomize**, simple et sans templates |
| Distribuer ton application à d'autres équipes, avec beaucoup d'options | **Helm** |
| Rollback et historique par release | **Helm** |
| Aucun outil à installer | **Kustomize** |

Quand tu ne sais pas, commence par **Kustomize** pour tes propres applications. Tu rencontreras Helm dès que tu installeras un logiciel tiers.

---

## 6. Installer Helm sur Windows

Kustomize est déjà dans `kubectl` : rien à installer. Pour Helm :

```powershell
winget install Helm.Helm
```

Le téléchargement fait quelques dizaines de Mo. **Ferme complètement PowerShell et rouvre-le** (comme pour Minikube : un terminal déjà ouvert ne voit pas le nouveau PATH), puis :

```powershell
helm version
```

Si `winget` ne marche pas, une alternative est `choco install kubernetes-helm` (si tu as Chocolatey) ou le téléchargement de l'exécutable depuis la page des versions de Helm.

---

## 7. Commandes essentielles du module

| Commande | Ce qu'elle fait |
|----------|-----------------|
| `kubectl kustomize <dossier>` | Affiche le YAML final de Kustomize |
| `kubectl apply -k <dossier>` | Applique un dossier Kustomize |
| `kubectl diff -k <dossier>` | Montre les différences avec le cluster |
| `kubectl delete -k <dossier>` | Supprime ce que le dossier définit |
| `helm lint <chart>` | Vérifie un chart |
| `helm template <nom> <chart> -f <values>` | Affiche le YAML généré |
| `helm install <nom> <chart> -n <ns> --create-namespace` | Installe une release |
| `helm upgrade --install <nom> <chart>` | Installe ou met à jour (idempotent) |
| `helm list -A` | Liste les releases de tous les namespaces |
| `helm history <nom> -n <ns>` | Révisions d'une release |
| `helm rollback <nom> <révision> -n <ns>` | Revient à une révision |
| `helm uninstall <nom> -n <ns>` | Supprime une release |

---

## 8. Pratique

> **Images :** tout ce module utilise `nginx:1.27`, déjà chez toi. Seul **l'installation de Helm** demande un petit téléchargement (une vingtaine de Mo).
>
> Les fichiers ont été vérifiés en rendu (Kustomize 5.4 et Helm 4.3 : `lint` et `template`), mais pas exécutés sur ton cluster : si une commande te surprend, envoie-moi le message.

Commandes pour **PowerShell**, depuis le dossier du module.

## Partie A : Kustomize

### Étape 1 : Lire le résultat sans rien appliquer

```powershell
kubectl kustomize kustomize/base
kubectl kustomize kustomize/overlays/dev
kubectl kustomize kustomize/overlays/test
```

Compare les trois sorties : le namespace, le nombre de réplicas, les labels `env`, le nom du ConfigMap avec son hash, et les ressources du test.

### Étape 2 : Déployer dev et test

```powershell
kubectl apply -k kustomize/overlays/dev
kubectl apply -k kustomize/overlays/test
kubectl get deployments,pods,cm -n dev
kubectl get deployments,pods,cm -n test
```

Le même modèle, deux environnements : 1 réplica en `dev`, 3 en `test`.

### Étape 3 : Vérifier la configuration

```powershell
kubectl exec deploy/web -n dev -- env
kubectl exec deploy/web -n test -- env
kubectl get pods -A -l env=dev
```

`APP_ENV` et `LOG_LEVEL` diffèrent selon l'environnement.

### Étape 4 : Changer la config et voir le redéploiement automatique

Dans `kustomize/overlays/dev/kustomization.yaml`, change `LOG_LEVEL=debug` en `LOG_LEVEL=warn`. Puis :

```powershell
kubectl diff -k kustomize/overlays/dev
kubectl apply -k kustomize/overlays/dev
kubectl get pods -n dev
kubectl get cm -n dev
```

Le ConfigMap a un **nouveau nom (nouveau hash)**, les Pods ont été redéployés automatiquement, et l'ancien ConfigMap est resté (Kustomize ne nettoie pas seul).

### Étape 5 : Nettoyer

```powershell
kubectl delete -k kustomize/overlays/dev
kubectl delete -k kustomize/overlays/test
```

## Partie B : Helm

### Étape 6 : Installer Helm

```powershell
winget install Helm.Helm
```

Ferme et rouvre PowerShell, puis `helm version`.

### Étape 7 : Vérifier le chart sans rien installer

```powershell
helm lint helm/boutique-web
helm template web-dev helm/boutique-web -f helm/boutique-web/values-dev.yaml -n helm-dev
```

Lis le YAML généré : repère `replicas: 1`, le ConfigMap, et comment `{{ .Values... }}` est devenu des valeurs réelles. Teste aussi :

```powershell
helm template web helm/boutique-web --set ingress.enabled=true
```

Une ressource `Ingress` apparaît : c'est le `{{- if }}` du template.

### Étape 8 : Installer deux releases du même chart

```powershell
helm install web-dev helm/boutique-web -n helm-dev --create-namespace -f helm/boutique-web/values-dev.yaml
helm install web-test helm/boutique-web -n helm-test --create-namespace -f helm/boutique-web/values-test.yaml
helm list -A
kubectl get deployments,pods,cm,svc -n helm-dev
kubectl get deployments,pods,cm,svc -n helm-test
kubectl get secrets -n helm-dev
```

Dans les Secrets, repère `sh.helm.release.v1.web-dev.v1` : c'est l'historique de Helm.

### Étape 9 : Mettre à jour et consulter l'historique

```powershell
helm upgrade web-dev helm/boutique-web -n helm-dev -f helm/boutique-web/values-dev.yaml --set replicaCount=3
helm history web-dev -n helm-dev
kubectl get pods -n helm-dev
helm get values web-dev -n helm-dev
```

### Étape 10 : Casser la release, puis revenir en arrière

```powershell
helm upgrade web-dev helm/boutique-web -n helm-dev -f helm/boutique-web/values-dev.yaml --set image.tag=nexiste-pas
helm status web-dev -n helm-dev
kubectl get pods -n helm-dev
```

Helm affiche `deployed`, **mais** des Pods sont en `ImagePullBackOff` : sans `--wait`, il ne vérifie pas la santé. Reviens en arrière :

```powershell
helm history web-dev -n helm-dev
helm rollback web-dev 2 -n helm-dev
kubectl get pods -n helm-dev
```

(Choisis le numéro d'une révision saine dans l'historique.) Refais ensuite la mauvaise mise à jour **avec** attente :

```powershell
helm upgrade web-dev helm/boutique-web -n helm-dev -f helm/boutique-web/values-dev.yaml --set image.tag=nexiste-pas --wait --timeout 60s
```

Au bout de 60 secondes, Helm signale l'échec.

### Étape 11 : Nettoyer

```powershell
helm uninstall web-dev -n helm-dev
helm uninstall web-test -n helm-test
kubectl delete namespace helm-dev helm-test
```

---

## 9. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `error converting YAML to JSON` (Helm) | Mauvaise indentation après `toYaml` ou `include` | Utilise `nindent` avec le bon nombre d'espaces ; vérifie avec `helm template` |
| `nil pointer evaluating interface` | Une valeur n'existe pas dans `values.yaml` | Ajoute-la avec une valeur par défaut, ou utilise `default` |
| `helm` introuvable après l'installation | Terminal ouvert avant l'installation | Ferme et rouvre PowerShell |
| Release `deployed` mais application cassée | Helm n'attend pas la santé sans `--wait` | Ajoute `--wait --timeout 2m` |
| `cannot re-use a name that is still in use` | Une release de ce nom existe | `helm list -A`, ou utilise `helm upgrade --install` |
| `rendered manifests contain a resource that already exists` | La ressource a été créée sans Helm | Supprime-la ou change de nom/namespace |
| `must specify` / rendu vide | Mauvais chemin vers le chart | Vérifie que `Chart.yaml` est dans le dossier indiqué |
| `no matches for kind` (Kustomize) | Champ obsolète ou version incompatible | Lance `kubectl kustomize` pour voir l'erreur exacte |
| `field is immutable` après Kustomize | Un label a été ajouté aux selectors | Utilise `labels` avec `includeSelectors: false` |
| Anciens ConfigMaps qui s'accumulent | Kustomize n'en supprime pas seul | Nettoie à la main, ou utilise `--prune` |
| Mauvais environnement modifié | Mauvais namespace ou contexte | Vérifie `kubectl config view --minify` et lis `kubectl diff -k` avant d'appliquer |

---

## 10. Points clés à retenir

- On évite la duplication : **un modèle commun** et **des différences par environnement**.
- **Kustomize** : base + overlays, YAML toujours valide, déjà dans `kubectl`. Affiche avec `kubectl kustomize`, applique avec `kubectl apply -k`.
- **Helm** : **chart** + **values** = **release**, avec historique et rollback.
- Priorité des valeurs Helm : `values.yaml` < `-f` < `--set`.
- Le **hash** du ConfigMap (Kustomize) ou l'annotation `checksum/config` (Helm) redéploient les Pods quand la configuration change.
- Helm ne vérifie pas la santé sans **`--wait`**.
- Avant d'appliquer, **regarde toujours le rendu** : `kubectl kustomize`, `kubectl diff -k`, `helm template`, `helm lint`.
- Pour tes propres applications, **Kustomize** est souvent suffisant ; **Helm** s'impose pour les logiciels tiers.

## ✅ Checklist

- [ ] Je sais expliquer pourquoi on évite de copier les YAML entre environnements
- [ ] Je sais structurer une base et des overlays Kustomize
- [ ] Je sais utiliser `replicas`, `labels`, `patches` et `configMapGenerator`
- [ ] Je sais prévisualiser avec `kubectl kustomize` et `kubectl diff -k`
- [ ] Je sais expliquer chart, values, release et revision
- [ ] Je sais lire un template Helm (`.Values`, `if`, `range`, `include`, `nindent`)
- [ ] Je sais installer, mettre à jour, faire un rollback et désinstaller une release
- [ ] Je sais pourquoi `--wait` est important
- [ ] Je sais choisir entre Helm et Kustomize selon la situation

**Suite :** [09 - CI/CD](../09-ci-cd/README.md) (GitHub Actions, déploiement automatique sur Kubernetes)
