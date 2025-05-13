Set Deployment URLs Action
==========================

Cette action GitHub génère des URLs de déploiement standardisées pour différents environnements de DetectXpert. Elle permet de créer des URLs cohérentes pour votre application principale, API, tableau de bord et documentation.

📑 Table des matières
---------------------

-   [Fonctionnalités](#-fonctionnalit%C3%A9s)
-   [Installation](#-installation)
-   [Paramètres](#%EF%B8%8F-param%C3%A8tres)
-   [Sorties](#-sorties)
-   [Format JSON](#-format-json)
-   [Exemples d'utilisation](#-exemples-dutilisation)
-   [Conventions d'URL](#-conventions-durl)
-   [Tests](#-tests)
-   [Développement](#-d%C3%A9veloppement)

📋 Fonctionnalités
------------------

-   ✅ Génération d'URLs standardisées basées sur l'environnement
-   ✅ Support pour préfixe personnalisé remplaçant l'environnement
-   ✅ Option pour inclure la version dans l'URL
-   ✅ Validation robuste des entrées
-   ✅ Sortie au format GitHub Actions et/ou JSON
-   ✅ Support multilingue (français/anglais)
-   ✅ ID de déploiement unique généré automatiquement

🚀 Installation
---------------

yaml

```
# Dans .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set Deployment URLs
        id: urls
        uses: ./.github/actions/set-deployment-urls
        with:
          environment: staging
          version: 1.2.3
```

⚙️ Paramètres
-------------

| Nom | Description | Requis | Type | Défaut |
| --- | --- | --- | --- | --- |
| `environment` | Environnement de déploiement | ✅ | `string` | --- |
| `version` | Version du déploiement (SemVer recommandé) | ✅ | `string` | --- |
| `base-domain` | Domaine de base | ❌ | `string` | `detectxpert.com` |
| `include-version-in-url` | Inclure la version dans l'URL | ❌ | `boolean` | `false` |
| `custom-prefix` | Préfixe personnalisé (remplace l'environnement) | ❌ | `string` | --- |
| `use-https` | Utiliser HTTPS | ❌ | `boolean` | `true` |
| `path-prefix` | Préfixe de chemin (ex: `/app`) | ❌ | `string` | --- |
| `debug` | Mode debug (affiche les logs détaillés) | ❌ | `boolean` | `false` |
| `output-json` | Générer la sortie JSON | ❌ | `boolean` | `false` |
| `json-output-file` | Fichier où sauvegarder le JSON | ❌ | `string` | --- |
| `locale` | Langue des messages (`fr` ou `en`) | ❌ | `string` | `fr` |

📤 Sorties
----------

| Nom | Description | Exemple |
| --- | --- | --- |
| `main-url` | URL principale de l'application | `https://staging.detectxpert.com/` |
| `api-url` | URL de l'API | `https://api.staging.detectxpert.com/` |
| `dashboard-url` | URL du tableau de bord administrateur | `https://dashboard.staging.detectxpert.com/` |
| `docs-url` | URL de la documentation | `https://docs.staging.detectxpert.com/` |
| `deployment-id` | Identifiant unique du déploiement | `staging-1.2.3-20250512120000` |
| `json` | Sortie JSON complète (si `output-json: true`) | Voir [Format JSON](#-format-json) |

📊 Format JSON
--------------

Si `output-json: true`, l'action génère également une sortie JSON structurée :

json

```
{
  "main_url": "https://staging.detectxpert.com/",
  "api_url": "https://api.staging.detectxpert.com/",
  "dashboard_url": "https://dashboard.staging.detectxpert.com/",
  "docs_url": "https://docs.staging.detectxpert.com/",
  "deployment_id": "staging-1.2.3-20250512120000",
  "environment": "staging",
  "version": "1.2.3",
  "include_version_in_url": false,
  "custom_prefix": "",
  "use_https": true,
  "base_domain": "detectxpert.com",
  "timestamp": "20250512120000"
}
```

📝 Exemples d'utilisation
-------------------------

### Utilisation basique

yaml

```
- name: Set URLs (basic)
  id: urls
  uses: ./.github/actions/set-deployment-urls
  with:
    environment: staging
    version: 1.2.3

- name: Show URLs
  run: |
    echo "Main URL: ${{ steps.urls.outputs.main-url }}"
    echo "API URL: ${{ steps.urls.outputs.api-url }}"
```

### Avec version dans l'URL

yaml

```
- name: Set URLs with Version
  id: urls
  uses: ./.github/actions/set-deployment-urls
  with:
    environment: prod
    version: 2.0.0
    include-version-in-url: true

# Résultat: https://prod.detectxpert.com/v2.0.0/
```

### Avec sortie JSON et traitement

yaml

```
- name: Set URLs with JSON Output
  id: urls
  uses: ./.github/actions/set-deployment-urls
  with:
    environment: staging
    version: 1.2.3
    output-json: true
    json-output-file: ./deployment-urls.json

- name: Parse JSON output
  run: |
    # Lire directement depuis la sortie
    echo "${{ steps.urls.outputs.json }}" | jq '.main_url'

    # Ou depuis le fichier
    cat ./deployment-urls.json | jq '.api_url'
```

📋 Conventions d'URL
--------------------

| Env | Version | Préfixe | Path | Main URL |
| --- | --- | --- | --- | --- |
| `staging` | `1.2.3` | --- | --- | `https://staging.detectxpert.com/` |
| `staging` | `1.2.3` | --- | `/v1.2.3` | `https://staging.detectxpert.com/v1.2.3/` |
| --- | `1.2.3` | `demo` | `/v1.2.3` | `https://demo.detectxpert.com/v1.2.3/` |
| `staging` | `1.2.3` | --- | `/app` | `https://staging.detectxpert.com/app/` |
| `prod` | `2.0.0` | --- | --- | `http://prod.detectxpert.com/` <br>(avec `use-https: false`) |

🧪 Tests
--------

Cette action est testée avec [Bats](https://github.com/bats-core/bats-core). Les tests couvrent :

-   Validation d'entrée (environnement, version, domaine, préfixe)
-   Différentes configurations de chemin
-   i18n (messages en français et anglais)
-   Génération JSON avec et sans `jq`
-   Options de version dans l'URL

Pour exécuter les tests :

bash

```
# Installer Bats
npm install -g bats

# Exécuter les tests
bats tests/set-deployment-urls.bats
```

Les fichiers de test se trouvent dans le dossier [tests/](./tests/).

🔧 Développement
----------------

Pour modifier cette action :

1.  Clonez le dépôt
2.  Modifiez les fichiers selon vos besoins
3.  Ajoutez ou modifiez les tests unitaires dans [tests/set-deployment-urls.bats](./tests/set-deployment-urls.bats)
4.  Vérifiez que tous les tests passent
5.  Créez une pull request

📄 Licence
----------

Ce projet est sous licence MIT - voir le fichier <LICENSE> pour plus de détails.

🤝 Contribution
---------------

Les contributions sont les bienvenues ! N'hésitez pas à ouvrir une issue ou une pull request.Previous-Version Action
=======================

[Afficher l'image](https://github.com/detectxpert/actions/actions/workflows/ci.yml) [Afficher l'image](https://github.com/detectxpert/actions) [Afficher l'image](https://github.com/detectxpert/actions/commits/main)

Action GitHub personnalisée pour récupérer et gérer les informations relatives aux versions précédentes de l'application DetectXpert.

Sommaire
--------

-   [Description](#description)
-   [Fonctionnalités](#fonctionnalit%C3%A9s)
-   [Installation](#installation)
-   [Utilisation](#utilisation)
-   [Inputs](#inputs)
-   [Outputs](#outputs)
-   [Exemples avancés](#exemples-avanc%C3%A9s)
-   [Dépendances](#d%C3%A9pendances)
-   [Dépannage](#d%C3%A9pannage)
-   [Maintenance](#maintenance)
-   [Documentation interne](#documentation-interne)
-   [Licence et contributions](#licence-et-contributions)
-   [Contact](#contact)

Description
-----------

Cette action facilite la comparaison entre versions, la gestion des migrations et assure la rétrocompatibilité en fournissant un accès automatisé aux métadonnées des versions précédentes.

Fonctionnalités
---------------

-   ✅ Récupération automatique du numéro de version précédente depuis les tags Git
-   ✅ Extraction des métadonnées associées à la version précédente
-   ✅ Comparaison structurelle entre la version actuelle et la version précédente
-   ✅ Support pour la génération de notes de migration
-   ✅ Identification des changements incompatibles (breaking changes)

Installation
------------

Cette action fait partie intégrante du dépôt DetectXpert et se trouve dans le répertoire `.github/actions/previous-version/`. Elle ne nécessite pas d'installation externe.

Structure des fichiers:

```
.github/
  └── actions/
      └── previous-version/
          ├── action.yml
          ├── previous-version.sh
          └── README.md
```

Utilisation
-----------

Dans votre workflow GitHub Actions, intégrez la référence à cette action :

yaml

```
steps:
  - uses: actions/checkout@v3
    with:
      fetch-depth: 0

  - name: Get Previous Version
    id: prev-version
    uses: ./.github/actions/previous-version
```

Inputs
------

| Nom | Description | Requis | Valeur par défaut |
| --- | --- | --- | --- |
| `format` | Format de sortie de la version | Non | `semver` |
| `prefix` | Préfixe utilisé pour les tags de version | Non | `v` |
| `include-prerelease` | Inclure les versions de pré-release | Non | `false` |
| `repo-token` | Token GitHub pour accéder aux tags/releases | Oui | --- |
| `skip-checkout` | Ignorer l'étape de checkout intégrée | Non | `false` |
| `version-pattern` | Regex pour filtrer les versions | Non | `v[0-9]+\.[0-9]+\.[0-9]+.*` |

Outputs
-------

| Nom | Description | Exemple |
| --- | --- | --- |
| `version` | Numéro de la version précédente | `1.2.3` |
| `tag` | Le tag Git complet de la version précédente | `v1.2.3` |
| `release-date` | Date de publication de la version précédente | `2023-01-15` |
| `commit-sha` | Hash du commit correspondant à la version précédente | `7a23d5e2b3...` |
| `major` | Composante majeure de la version | `1` |
| `minor` | Composante mineure de la version | `2` |
| `patch` | Composante de correctif de la version | `3` |
| `previous-version-tag` | Tag complet (avec préfixe, pré-release, build) | `v1.2.3-beta+001` |

Exemples avancés
----------------

### Exemple complet de workflow de release

yaml

```
name: Release Workflow

on:
  workflow_dispatch:
    inputs:
      version_type:
        description: 'Type de version (major, minor, patch)'
        required: true
        default: 'patch'

jobs:
  prepare-release:
    runs-on: ubuntu-latest
    steps:
      # Étape 1: Checkout du code
      - name: Checkout repository
        uses: actions/checkout@v3
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      # Étape 2: Récupération de la version précédente
      - name: Get Previous Version
        id: prev-version
        uses: ./.github/actions/previous-version
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}

      # Étape 3: Calcul de la nouvelle version
      - name: Bump Version
        id: bump-version
        uses: ./.github/actions/version-info
        with:
          current-version: ${{ steps.prev-version.outputs.version }}
          increment: ${{ github.event.inputs.version_type }}

      # Étape 4: Génération du changelog
      - name: Generate Changelog
        id: changelog
        uses: ./.github/actions/generate-changelog
        with:
          previous-version: ${{ steps.prev-version.outputs.tag }}
          current-version: v${{ steps.bump-version.outputs.version }}
          token: ${{ secrets.GITHUB_TOKEN }}

      # Étape 5: Création de la release
      - name: Create Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: v${{ steps.bump-version.outputs.version }}
          release_name: Release v${{ steps.bump-version.outputs.version }}
          body: |
            ## Changements depuis ${{ steps.prev-version.outputs.tag }}

            ${{ steps.changelog.outputs.content }}

            Pour plus d'informations, consultez la [documentation de migration](docs/migration/${{ steps.bump-version.outputs.version }}.md).
          draft: false
          prerelease: false
```

### Test de migration entre versions

bash

```
# Récupération de la version précédente
previous_version=$(cat .github/actions/previous-version/previous-version.sh | bash)

# Test de migration des données
echo "Testing migration from ${previous_version} to ${current_version}"
./scripts/test-migration.sh "${previous_version}" "${current_version}"
```

Dépendances
-----------

-   Git installé sur le runner (version 2.18+)
-   Bash shell (version 4.0+)
-   jq pour le traitement JSON (installé sur les runners GitHub par défaut)

Dépannage
---------

### La version précédente n'est pas détectée correctement

Assurez-vous que :

-   Votre dépôt contient bien des tags de version formatés correctement (ex: v1.2.3)
-   Vous avez cloné le dépôt avec `fetch-depth: 0` pour accéder à l'historique complet
-   Les permissions Git sont correctement configurées
-   Le token GitHub a les droits suffisants pour accéder aux releases

### Erreur "No previous version found"

Cette erreur peut se produire si :

-   C'est la première release du projet
-   Le pattern de version ne correspond à aucun tag existant
-   L'historique Git n'est pas complet (vérifiez le `fetch-depth`)

Maintenance
-----------

Pour modifier le comportement de détection des versions précédentes :

-   Mettez à jour le script `previous-version.sh` pour la logique de détection
-   Modifiez le fichier `action.yml` pour changer les entrées/sorties ou les métadonnées

Documentation interne
---------------------

Pour plus de détails sur le fonctionnement interne du script et des informations spécifiques au développement de cette action, consultez :

-   [Documentation du script](../.github/actions/previous-version/README-dev.md)
-   [Spécifications de versionnage](../docs/versioning.md)

Licence et contributions
------------------------

Cette action est distribuée sous licence MIT. Voir le fichier [LICENSE](../LICENSE) pour plus de détails.

Toute contribution est la bienvenue ! Si vous souhaitez améliorer cette action :

1.  Créez une fork du dépôt
2.  Créez une branche pour votre fonctionnalité (`git checkout -b feature/amazing-feature`)
3.  Commitez vos changements (`git commit -m 'Add some amazing feature'`)
4.  Poussez vers la branche (`git push origin feature/amazing-feature`)
5.  Ouvrez une Pull Request

Contact
-------

Pour toute question sur cette action, veuillez ouvrir une issue sur le [dépôt GitHub](https://github.com/detectxpert/actions/issues).

* * * * *