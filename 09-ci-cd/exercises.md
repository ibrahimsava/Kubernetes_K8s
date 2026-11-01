# Exercices - Module 09

Fais ces exercices sans regarder le cours. Note tes observations dans `../notes/`.

> 💡 Toute la partie obligatoire s'exécute **sur GitHub**, dans le cloud : aucun téléchargement lourd sur ton PC.
>
> Commandes Git pour **PowerShell**. Travaille sur une **branche** pour chaque expérience, pas directement sur `main`.

---

## Exercice 1 : Lire un workflow

Ouvre `.github/workflows/validate-k8s.yml` et réponds sans exécuter quoi que ce soit :

1. Quels événements le déclenchent ?
2. Combien de jobs contient-il ? Sur quelle machine s'exécute-t-il ?
3. Que fait le bloc `concurrency` ? Dans quel cas est-il utile ?
4. Pourquoi `permissions: contents: read` est-il déclaré tout en haut ?
5. Pourquoi les manifests de `08-helm-kustomize/` sont-ils exclus de la première validation, puis validés séparément ?
6. Quelle commande transforme le chart Helm en YAML avant la validation ?

**Question piège :** que se passe-t-il si tu supprimes l'étape `Checkout` ? Pourquoi ?

---

## Exercice 2 : Casser puis réparer, depuis une pull request 🔧

1. Crée une branche : `git switch -c exercice-casse`.
2. Dans `04-configuration/manifests/configmap.yaml`, change `kind: ConfigMap` en `kind: ConfigMapp` (deux `p`) pour un des deux documents, ou dans un autre manifest mets un champ obligatoire de mauvais type.
3. Commite, pousse (`git push -u origin exercice-casse`) et ouvre une **pull request** vers `main`.
4. Lis le message d'erreur dans l'onglet Actions : quel fichier et quelle ressource sont désignés ?
5. Corrige, pousse, et observe le contrôle repasser au vert **sans rien relancer à la main**.

**Questions**
- À quelle étape exacte du pipeline l'erreur est-elle détectée ?
- Combien de temps as-tu gagné par rapport à une découverte sur le cluster ?
- Pourquoi est-il important que ce contrôle bloque la fusion dans `main` ?

---

## Exercice 3 : Protéger `main`

1. Dans *Settings → Branches*, crée une règle pour `main` qui exige que le contrôle `validate` réussisse avant de fusionner.
2. Retente la pull request cassée de l'exercice 2 (ou refais-en une) : le bouton de fusion est-il bloqué ?

**Questions**
- Quelle différence entre un pipeline qui **informe** et un pipeline qui **bloque** ?
- Pourquoi le nom du contrôle exigé doit-il correspondre au `name` du job ?

---

## Exercice 4 : Étendre la validation avec une matrice 🔧

Modifie `validate-k8s.yml` pour valider les manifests **contre deux versions de Kubernetes** (par exemple `1.30.0` et `1.31.0`) à l'aide d'une matrice :

```yaml
strategy:
  matrix:
    k8s-version: ["1.30.0", "1.31.0"]
```

Remplace l'utilisation de `K8S_VERSION` par `${{ matrix.k8s-version }}`.

**Questions**
- Combien d'exécutions du job vois-tu dans l'onglet Actions ?
- Dans quel cas une validation sur plusieurs versions est-elle utile ?
- Que faut-il changer si un des deux jobs de la matrice échoue : les autres s'arrêtent-ils ? (Cherche `fail-fast`.)

---

## Exercice 5 : Déclenchement manuel avec un paramètre

Ajoute à `kind-deploy.yml` un déclencheur manuel avec un paramètre :

```yaml
workflow_dispatch:
  inputs:
    release-name:
      description: "Nom de la release Helm"
      required: false
      default: "web-ci"
```

Utilise `${{ inputs.release-name }}` dans l'étape de déploiement Helm (attention : le nom du Service dépend du nom de la release).

**Questions**
- Comment lances-tu le workflow à la main depuis GitHub ?
- Que se passe-t-il pour `inputs.release-name` quand le workflow est déclenché par un `push` ?

---

## Exercice 6 : Secrets et variables

1. Crée un secret `DEMO_SECRET` dans *Settings → Secrets and variables → Actions*, avec une **fausse** valeur.
2. Crée un petit workflow `secret-demo.yml` :
   ```yaml
   name: Secret demo
   on: workflow_dispatch
   permissions:
     contents: read
   jobs:
     demo:
       runs-on: ubuntu-latest
       steps:
         - name: Utiliser le secret
           env:
             MON_SECRET: ${{ secrets.DEMO_SECRET }}
           run: |
             echo "Longueur : ${#MON_SECRET}"
             echo "Valeur : $MON_SECRET"
   ```
3. Lance-le à la main et lis les logs.
4. **Supprime ensuite** ce workflow et le secret.

**Questions**
- Comment la valeur apparaît-elle dans les logs ?
- Cela signifie-t-il qu'afficher un secret est sans danger ? (Pense à `base64`, à l'inversion de la chaîne...)
- Pourquoi passe-t-on le secret par `env:` plutôt que de l'écrire directement dans la commande `run:` ?

---

## Exercice 7 : Concevoir le pipeline de ton API Spring Boot 🔧

Sans copier le modèle, écris sur papier (ou dans `notes/`) les étapes d'un pipeline pour ton API :

1. Quels **événements** déclenchent chaque partie ?
2. Dans quel **ordre** et avec quelles dépendances (`needs`) ?
3. Quelle **permission** supplémentaire faut-il pour publier l'image ?
4. Comment l'image est-elle **taguée** ? Pourquoi ?
5. Comment le pipeline **vérifie-t-il** que le déploiement a réussi ?
6. Que se passe-t-il **en cas d'échec** ?
7. Qui doit **valider** avant la production ?

Compare ensuite avec `09-ci-cd/templates/build-push-deploy.yml`.

**Questions**
- Pourquoi le job `build-push` est-il ignoré sur les pull requests (`if: github.event_name != 'pull_request'`) ?
- Pourquoi le modèle utilise-t-il `outputs` pour passer le nom de l'image d'un job à l'autre ?

---

## Exercice 8 : Audit de sécurité 🔍

Voici un workflow volontairement mal écrit. Trouve **tous** les problèmes et propose une correction pour chacun :

```yaml
name: Deploy
on:
  pull_request_target:
  push:
permissions: write-all
jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - uses: un-inconnu/super-deploy@main
      - run: |
          echo "Mot de passe : ${{ secrets.DB_PASSWORD }}"
          docker build -t monapp:latest .
          kubectl apply -f k8s/
```

**Indices à chercher :** déclencheurs dangereux, permissions trop larges, code d'un inconnu exécuté sur ta machine, action tierce non épinglée, secret affiché, tag `latest`, pas de vérification du rollout, pas de rollback.

**Questions**
- Quel est le **pire** problème de cette liste, et pourquoi ?
- Qu'est-ce qui rend `pull_request_target` combiné à un checkout du code de la PR si dangereux ?

---

## Exercice 9 : Déployer, vérifier, revenir en arrière

Écris (dans un fichier de notes) les trois commandes `kubectl` d'un déploiement sûr, puis l'étape GitHub Actions qui annule le déploiement en cas d'échec :

1. appliquer les manifests
2. mettre l'image à jour avec le SHA du commit
3. attendre le rollout avec un délai
4. étape conditionnelle de rollback

Compare avec le job `deploy-dev` du modèle.

**Questions**
- Que se passe-t-il si `rollout status` dépasse le délai ?
- Pourquoi les readiness probes (module 06) sont-elles indispensables à ce mécanisme ?
- Que verrait-on si l'application démarrait mais répondait des erreurs 500 ? Comment le détecter automatiquement ?

---

## Exercice 10 : Push ou GitOps ? (réflexion)

Remplis un tableau comparant le modèle « le pipeline déploie » et le modèle « Argo CD / Flux » :

| Critère | Pipeline (push) | GitOps (pull) |
|---------|-----------------|---------------|
| Le cluster doit-il être joignable depuis Internet ? | ? | ? |
| Où sont stockés les identifiants du cluster ? | ? | ? |
| Que se passe-t-il si quelqu'un modifie le cluster à la main ? | ? | ? |
| Quelle est la source de vérité ? | ? | ? |
| Comment revient-on en arrière ? | ? | ? |

---

## Questions d'auto-évaluation

1. Quelle est la différence entre CI, Continuous Delivery et Continuous Deployment ?
2. Où doivent se trouver les fichiers de workflow ?
3. Quelle différence entre un workflow, un job et un step ?
4. Pourquoi les workflows GitHub s'exécutent-ils sans solliciter ta connexion Internet locale ?
5. Pourquoi GitHub ne peut-il pas déployer directement sur ton Minikube ?
6. Pourquoi tague-t-on les images avec le SHA du commit ?
7. À quoi sert `permissions:` dans un workflow ?
8. Quels sont les risques d'un runner auto-hébergé sur un repo public ?
9. Qu'apporte un environnement protégé (`environment: production`) ?
10. Que fait `kubectl rollout status` dans un pipeline, et pourquoi est-il essentiel ?

---

## Nettoyage

```powershell
git switch main
git branch -D exercice-casse test-erreur
git push origin --delete exercice-casse test-erreur
```

Supprime aussi dans GitHub les secrets de test (`DEMO_SECRET`) et le workflow `secret-demo.yml` s'il existe encore.