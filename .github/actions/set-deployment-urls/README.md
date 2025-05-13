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

Les contributions sont les bienvenues ! N'hésitez pas à ouvrir une issue ou une pull request.