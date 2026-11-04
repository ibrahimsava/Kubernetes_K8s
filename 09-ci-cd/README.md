# 09 - CI/CD : GitHub Actions et déploiement sur Kubernetes

> **Objectif du module :** automatiser la vérification, la construction et le déploiement de ton application, pour que chaque `git push` soit contrôlé et que chaque déploiement soit reproductible.

**Durée estimée :** 4 heures · **Prérequis :** modules 01 à 08 terminés, un repo GitHub

---

## 1. Le problème

Aujourd'hui, pour déployer, tu tapes des commandes à la main : `kubectl apply`, `helm upgrade`... Ça pose plusieurs problèmes :

- on **oublie** une étape, ou on la fait dans le mauvais ordre
- on déploie du code qui **ne compile pas** ou dont les **tests échouent**
- on se trompe de **cluster ou de namespace** (module 07)
- personne d'autre ne sait **ce qui a été déployé, quand et par qui**

La solution est un **pipeline** : une suite d'étapes exécutées automatiquement à chaque changement.

### CI, Continuous Delivery, Continuous Deployment

| Sigle | Signification | Ce que ça fait |
|-------|---------------|----------------|
| **CI** | Continuous Integration | À chaque push : compiler, tester, valider |
| **CD** (Delivery) | Continuous Delivery | Produire un artefact **prêt à déployer**, le déploiement final demande une validation humaine |
| **CD** (Deployment) | Continuous Deployment | Déployer **automatiquement** en production si tout passe |

---

## 2. GitHub Actions : les concepts

**GitHub Actions** est le moteur de pipelines intégré à GitHub. Tout est décrit dans des fichiers YAML du dossier `.github/workflows/` de ton repo.

| Concept | Description |
|---------|-------------|
| **Workflow** | Un fichier YAML décrivant un pipeline |
| **Event** (`on:`) | Ce qui le déclenche : `push`, `pull_request`, `workflow_dispatch`, `schedule`... |
| **Job** | Un groupe d'étapes exécuté sur **une machine** |
| **Step** | Une étape : une commande (`run:`) ou une action réutilisable (`uses:`) |
| **Runner** | La machine qui exécute le job (`ubuntu-latest`, ou **auto-hébergée**) |
| **Action** | Un composant réutilisable, par exemple `actions/checkout` |
| **Secret** | Une valeur sensible stockée dans GitHub |

> ⚠️ **Le fichier doit être dans `.github/workflows/` à la racine du repo**, avec l'extension `.yml` ou `.yaml`. Placé ailleurs, GitHub l'ignore.

### Anatomie d'un workflow

```yaml
name: Mon pipeline                     # nom affiché dans l'onglet Actions

on:                                    # déclencheurs
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:                   # lancement manuel

permissions:                           # droits du jeton GITHUB_TOKEN (moindre privilège)
  contents: read

jobs:
  validate:                            # identifiant du job
    runs-on: ubuntu-latest             # machine
    steps:
      - name: Checkout                 # étape : récupérer le code
        uses: actions/checkout@v4
      - name: Dire bonjour             # étape : une commande
        run: echo "Commit ${{ github.sha }}"
```

### La syntaxe essentielle

| Élément | Rôle | Exemple |
|---------|------|---------|
| `needs` | Ordonne les jobs | `needs: test` |
| `if` | Condition | `if: github.ref == 'refs/heads/main'` |
| `env` | Variables d'environnement | `env: { K8S_VERSION: "1.31.0" }` |
| `${{ secrets.NOM }}` | Lit un secret | `${{ secrets.GITHUB_TOKEN }}` |
| `${{ github.sha }}` | Identifiant du commit | Utilisé pour taguer les images |
| `paths` | Ne déclenche que si certains fichiers changent | `paths: ['project/**']` |
| `strategy.matrix` | Lance le job avec plusieurs variantes | Plusieurs versions de Java |
| `concurrency` | Évite les exécutions simultanées | Annule l'ancienne exécution |
| `environment` | Environnement avec règles (validation humaine, secrets propres) | `environment: production` |
| `outputs` | Passe une valeur d'un job à un autre | `${{ needs.build.outputs.image }}` |
| `if: failure()` | S'exécute **seulement si** une étape précédente a échoué | Diagnostic, rollback |

### Où voir les résultats ?

Onglet **Actions** de ton repo : chaque exécution, chaque job et chaque étape avec ses logs. Sur une pull request, les résultats apparaissent en bas, avec une coche verte ou une croix rouge.

---

## 3. Notre pipeline en trois niveaux

| Niveau | Fichier | État | Rôle |
|--------|---------|------|------|
| 1. Validation | `.github/workflows/validate-k8s.yml` | **Actif** | Vérifie tous tes manifests, tes overlays Kustomize et ton chart Helm |
| 2. Déploiement test | `.github/workflows/kind-deploy.yml` | **Actif** | Crée un cluster Kubernetes éphémère et y déploie vraiment l'application |
| 3. Build, push, deploy | `09-ci-cd/templates/build-push-deploy.yml` | **Modèle** | Pour ton futur projet Spring Boot (à activer plus tard) |

> 💡 **Avec ta connexion lente :** GitHub exécute les workflows **dans le cloud**, avec sa propre bande passante. Les téléchargements lourds (images, dépendances Maven) ne passent **pas** par ton PC. Ton seul effort réseau est un petit `git push`.

### Niveau 1 : validation des manifests

Fichier [`.github/workflows/validate-k8s.yml`](../.github/workflows/validate-k8s.yml). À chaque push et pull request, il :

1. installe **kubeconform**, un outil qui vérifie qu'un YAML est un manifest Kubernetes valide
2. valide tous les manifests « bruts » du repo
3. rend les overlays **Kustomize** (`kubectl kustomize`) et valide le résultat
4. passe `helm lint` sur le chart et valide le résultat de `helm template`

Une faute comme `replicas: "trois"` ou un champ inventé est détectée **avant** d'arriver sur un cluster.

### Niveau 2 : un vrai cluster dans le pipeline

Fichier [`.github/workflows/kind-deploy.yml`](../.github/workflows/kind-deploy.yml). Il utilise **kind** (Kubernetes dans Docker) pour créer un cluster temporaire dans le runner, puis :

1. déploie le chart Helm avec `--wait` (le pipeline échoue si les Pods ne deviennent pas prêts)
2. fait un test de fumée : une requête HTTP vers l'application
3. déploie aussi l'overlay Kustomize `dev` et attend le rollout
4. en cas d'échec, affiche l'état du cluster pour diagnostiquer

Le cluster disparaît à la fin : **aucun cluster externe n'est nécessaire**. C'est une façon très courante de tester des manifests ou un chart avant de les livrer.

### Niveau 3 : build, push et deploy

Le modèle [`templates/build-push-deploy.yml`](./templates/build-push-deploy.yml) enchaîne quatre jobs :

```
test  ──►  build-push  ──►  deploy-dev  ──►  deploy-prod
(mvn)      (image → GHCR)   (auto)           (validation humaine)
```

Il n'est pas actif tant que ton projet Spring Boot n'existe pas. Quand `project/` contiendra un `pom.xml`, un `Dockerfile` et des manifests, tu le copieras dans `.github/workflows/`.

---

## 4. Construire et publier l'image

### Le Dockerfile pour Spring Boot

Fichier [`templates/Dockerfile`](./templates/Dockerfile) : un **build en deux étapes**.

```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS build      # étape 1 : compiler
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline                # dépendances mises en cache
COPY src ./src
RUN mvn -B package -DskipTests

FROM eclipse-temurin:21-jre                     # étape 2 : image finale légère
WORKDIR /app
RUN useradd --system --uid 1001 appuser
COPY --from=build /app/target/*.jar app.jar
USER 1001                                       # pas de root
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

| Choix | Pourquoi |
|-------|----------|
| Deux étapes | L'image finale ne contient pas Maven ni le code source : plus petite et plus sûre |
| `COPY pom.xml` avant `src` | Le cache Docker réutilise les dépendances tant que le `pom.xml` ne change pas |
| JRE (pas JDK) | Plus léger en production |
| `USER 1001` | Le conteneur ne tourne pas en root |

Ajoute aussi un [`.dockerignore`](./templates/.dockerignore) pour ne pas envoyer `target/`, `.git/` ou `.env` dans le contexte de build.

### Le registry : GitHub Container Registry (GHCR)

Un **registry** stocke les images. GHCR (`ghcr.io`) est gratuit et intégré à GitHub. Le pipeline s'y connecte avec le jeton `GITHUB_TOKEN`, **sans mot de passe à créer**, à condition de déclarer :

```yaml
permissions:
  packages: write
```

L'image s'appelle `ghcr.io/ibrahimsava/boutique-api:<tag>`.

### Quel tag choisir ?

| Tag | Avantage | Inconvénient |
|-----|----------|--------------|
| **SHA du commit** (`a1b2c3d`) | **Unique et immuable** : on sait exactement quel code tourne | Moins lisible |
| Version (`1.4.2`) | Lisible | Demande une discipline de versions |
| `latest` | Pratique | **Dangereux en déploiement** : on ne sait pas quelle version tourne, et un redémarrage peut changer la version |

> **Règle :** déploie toujours un tag **précis** (le SHA), jamais `latest`.

---

## 5. Déployer sur le cluster : les options

| Option | Principe | Quand |
|--------|----------|-------|
| **Runner auto-hébergé** | Un programme sur **ton PC** exécute le job, avec accès à ton Minikube | Apprentissage avec un cluster local |
| **Kubeconfig en secret** | Le runner GitHub se connecte au cluster avec des identifiants stockés en secret | Cluster accessible depuis Internet |
| **Identité fédérée (OIDC)** | Le pipeline obtient des droits **temporaires** du cloud, sans secret durable | Production sur AWS, GCP, Azure |
| **GitOps** | Un agent **dans** le cluster tire les changements depuis Git (Argo CD, Flux) | Production moderne |

### Pourquoi GitHub ne peut pas atteindre ton Minikube

Les runners de GitHub sont dans le cloud. Ton Minikube tourne sur **ton PC**, derrière ta box : GitHub ne peut pas s'y connecter. D'où le **runner auto-hébergé**, qui lui s'exécute chez toi.

### ⚠️ Les risques d'un runner auto-hébergé

Un runner auto-hébergé **exécute du code sur ta machine**. Sur un repo **public**, une pull request venant d'un inconnu pourrait lancer du code arbitraire sur ton PC.

| Règle | Pourquoi |
|-------|----------|
| Ne déclenche les jobs de déploiement que sur `push` vers `main` | Une PR de fork ne doit jamais atteindre ton PC |
| N'utilise jamais un runner auto-hébergé pour des PR de forks | Exécution de code non fiable |
| Ne lance le runner que quand tu en as besoin | Il n'écoute pas en permanence |
| Préfère un repo **privé** pour un runner qui accède à ton cluster | Réduit l'exposition |

Dans ce module, le runner auto-hébergé est **optionnel**. Les niveaux 1 et 2 suffisent à apprendre l'essentiel sans rien exposer.

### GitOps, en deux mots

Dans le modèle « push » vu ci-dessus, le pipeline **pousse** vers le cluster. En **GitOps**, le pipeline met seulement à jour Git (par exemple le tag de l'image dans un overlay), et un outil installé **dans** le cluster (**Argo CD** ou **Flux**) détecte le changement et l'applique. Avantages : le cluster n'a pas à être joignable de l'extérieur, Git devient la source de vérité, et l'état est réconcilié en continu.

---

## 6. Sécuriser le pipeline

Un pipeline a souvent accès à tes secrets et à ton cluster : c'est une cible de choix.

| Règle | Détail |
|-------|--------|
| **Moindre privilège** pour `GITHUB_TOKEN` | Déclare `permissions: contents: read` en haut, et n'ajoute `packages: write` que dans le job qui publie |
| **Secrets** | Stocke-les dans *Settings → Secrets and variables → Actions*, jamais dans le code. Ils sont masqués dans les logs, mais ne les affiche jamais volontairement |
| **Secrets par environnement** | Les secrets de `production` ne sont accessibles qu'au job qui déploie en production |
| **Environnements protégés** | Exige une **validation humaine** avant `production` |
| **Épingler les actions** | `uses: actions/checkout@v4` suit une version majeure. Pour plus de sécurité, épingle sur le **SHA complet** d'un commit |
| **Actions tierces** | Une action tierce exécute du code dans ton pipeline : vérifie sa provenance |
| **Pull requests de forks** | Les secrets ne leur sont pas transmis, et c'est voulu |
| **Compte de service dédié** | Pas d'admin du cluster : utilise un ServiceAccount limité, comme `ci-deployer` du module 07 |
| **Mises à jour** | Active **Dependabot** pour tenir à jour les actions utilisées |

> **Versions des actions :** les versions majeures indiquées (`checkout@v4`, `setup-java@v4`, `build-push-action@v6`...) étaient valides à la rédaction. Vérifie sur la page GitHub de chaque action s'il existe une version plus récente.

### Le compte de service du pipeline

Au module 07, tu as vu `ci-deployer` : un ServiceAccount qui peut mettre à jour les Deployments du namespace `dev`, et rien d'autre. Vérifie ses droits :

```powershell
kubectl auth can-i patch deployments -n dev --as=system:serviceaccount:dev:ci-deployer
kubectl auth can-i get secrets -n dev --as=system:serviceaccount:dev:ci-deployer
kubectl auth can-i delete deployments -n prod --as=system:serviceaccount:dev:ci-deployer
```

Résultats attendus : `yes`, `no`, `no`. Si le pipeline est compromis, l'attaquant ne peut toucher qu'à ce namespace, et pas aux Secrets.

---

## 7. Vérifier et revenir en arrière

Un déploiement n'est pas terminé quand `kubectl apply` répond : il l'est quand les Pods sont **prêts**. Le modèle utilise donc :

```bash
kubectl rollout status deployment/api -n dev --timeout=180s
```

Cette commande **échoue** si le rollout n'aboutit pas dans le délai, et le job passe alors en rouge. L'étape suivante ne s'exécute qu'en cas d'échec :

```yaml
- name: Roll back on failure
  if: failure()
  run: kubectl rollout undo deployment/api -n dev
```

Tu retrouves ici les readiness probes (module 06) et les rollbacks (modules 02 et 08) : ce sont eux qui rendent un déploiement automatique **sûr**.

---

## 8. Pratique

> ℹ️ Toute la partie obligatoire se passe sur GitHub : tu n'as rien à installer et rien à télécharger, à part un `git push`.

### Étape 1 : Placer les workflows à la racine

Dans ton repo `k8s-learning`, le dossier `.github/workflows/` doit être **à la racine**, au même niveau que `01-fundamentals/` :

```
k8s-learning/
├── .github/
│   └── workflows/
│       ├── validate-k8s.yml
│       └── kind-deploy.yml
├── 01-fundamentals/
├── ...
└── 09-ci-cd/
```

> ⚠️ Si l'Explorateur Windows cache le dossier `.github`, active *Affichage → Éléments masqués*. Les dossiers commençant par un point sont parfois masqués.

### Étape 2 : Pousser et observer

```powershell
git add .
git commit -m "feat: add CI workflows and module 09"
git push
```

Sur GitHub, ouvre l'onglet **Actions**. Tu vois deux workflows démarrer. Clique sur **Validate Kubernetes manifests**, puis sur le job `validate`, et lis les logs de chaque étape. Il doit se terminer en vert.

### Étape 3 : Casser volontairement un manifest

```powershell
git switch -c test-erreur
```

Ouvre `02-workloads/manifests/deployment.yaml` et remplace `replicas: 3` par `replicas: "trois"`. Puis :

```powershell
git add .
git commit -m "test: manifest invalide"
git push -u origin test-erreur
```

Sur GitHub, ouvre une **pull request** de `test-erreur` vers `main`. Le contrôle devient **rouge** : ouvre le détail et repère le message de kubeconform qui indique le champ fautif. Corrige l'erreur, pousse à nouveau, et vois le contrôle repasser au vert **sans rien relancer à la main**.

### Étape 4 : Lire le déploiement sur kind

Dans l'onglet **Actions**, ouvre **Deploy test on kind** (il se lance quand `08-helm-kustomize/` change, ou à la demande). Pour le lancer à la main : *Actions → Deploy test on kind → Run workflow*. Lis les étapes : création du cluster, déploiement Helm, test de fumée, déploiement Kustomize.

### Étape 5 : Ajouter un badge au README

Dans le `README.md` principal, ajoute :

```markdown
![Validate](https://github.com/ibrahimsava/k8s-learning/actions/workflows/validate-k8s.yml/badge.svg)
```

Le badge affiche l'état du pipeline directement sur la page d'accueil du repo. ce qui est recommander

### Étape 6 : Protéger la branche `main`

*Settings → Branches → Add branch ruleset* (ou *Add rule*) : exige que le contrôle `validate` réussisse avant de fusionner une pull request. Le nom du contrôle correspond au `name` du job.

### Étape 7 (optionnelle, plus tard) : le runner auto-hébergé

Ne le fais **que** quand ton projet Spring Boot existe, et seulement avec ta connexion en bon état (le programme du runner fait une centaine de Mo) :

1. *Settings → Actions → Runners → New self-hosted runner*, puis suis les commandes proposées.
2. Ajoute le label `minikube` lors de la configuration.
3. Lance-le dans un terminal (`./run.cmd`) **seulement le temps du test**.
4. Dans le modèle, `shell: bash` suppose que Git for Windows (qui fournit Bash) est installé.

---

## 9. Erreurs courantes

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| Le workflow n'apparaît pas dans l'onglet Actions | Fichier hors de `.github/workflows/` à la racine, ou extension incorrecte | Vérifie le chemin exact |
| Le workflow ne se déclenche pas | Le filtre `branches` ou `paths` ne correspond pas | Relis le bloc `on:` ; teste avec `workflow_dispatch` |
| `Invalid workflow file` | Erreur d'indentation YAML (jamais de tabulations) | Utilise un éditeur avec validation YAML |
| `Resource not accessible by integration` | Le `GITHUB_TOKEN` n'a pas le droit demandé | Ajoute la permission nécessaire dans `permissions:` |
| `denied` ou `403` au push sur GHCR | Il manque `packages: write` | Ajoute-la au job qui publie |
| `ImagePullBackOff` dans le cluster sur une image GHCR | Le package est **privé** | Rends le package public, ou crée un `imagePullSecret` |
| `kubectl: command not found` | Le runner n'a pas `kubectl` | Installe-le sur le runner auto-hébergé |
| `secrets.XXX` est vide | Secret absent, mal nommé, ou PR venant d'un fork | Vérifie *Settings → Secrets* ; les forks n'y ont pas accès |
| kubeconform signale `could not find schema` | Ressource personnalisée (CRD) inconnue | Ajoute `-ignore-missing-schemas`, ou fournis le schéma |
| Un job échoue sur `exit code 1` sans explication | La commande a réussi partiellement | Ajoute `set -x` ou lis les logs de l'étape précédente |
| Runner auto-hébergé hors ligne | Le programme n'est pas lancé | Relance `./run.cmd` |
| Les jobs ne s'exécutent pas dans l'ordre voulu | `needs` manquant | Déclare les dépendances entre jobs |

---

## 10. Points clés à retenir

- Un **pipeline** automatise validation, build et déploiement : chaque changement est **contrôlé** et **traçable**.
- GitHub Actions : **workflow** → **jobs** → **steps**, déclenchés par des **events**, dans `.github/workflows/` à la racine.
- Les workflows s'exécutent **dans le cloud de GitHub** : ta connexion lente n'est pas un obstacle.
- Valide tes manifests **avant** de déployer (kubeconform, `helm lint`, rendu Kustomize).
- Un cluster **kind éphémère** permet de tester un déploiement complet sans cluster externe.
- Tague les images avec le **SHA du commit**, jamais `latest` en déploiement.
- Un déploiement est réussi quand **`rollout status`** réussit, avec un **rollback** automatique sinon.
- **Moindre privilège** : `permissions` minimales, secrets par environnement, ServiceAccount dédié, validation humaine avant la production.
- Un **runner auto-hébergé** exécute du code sur ta machine : jamais pour des PR de forks.
- Le **GitOps** (Argo CD, Flux) inverse le modèle : le cluster tire ses changements depuis Git.

## ✅ Checklist

- [ ] Je sais expliquer CI, Continuous Delivery et Continuous Deployment
- [ ] Je sais lire un workflow : `on`, `jobs`, `steps`, `needs`, `if`, `permissions`
- [ ] Mes workflows sont à la racine dans `.github/workflows/` et s'exécutent en vert
- [ ] J'ai vu un contrôle devenir rouge sur une pull request, puis vert après correction
- [ ] Je sais pourquoi on tague les images avec le SHA et pas avec `latest`
- [ ] Je sais expliquer pourquoi GitHub ne peut pas atteindre mon Minikube
- [ ] Je connais les risques d'un runner auto-hébergé
- [ ] Je sais ce que fait `rollout status` et comment déclencher un rollback en cas d'échec
- [ ] Je sais citer quatre bonnes pratiques de sécurité d'un pipeline

**Suite :** [10 - Observabilité](../10-observability/README.md) (logs, métriques, Prometheus et Grafana)