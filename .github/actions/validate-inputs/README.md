markdown

```
# Validate Inputs Action

> **Version**: 1.1.0

Cette action valide les entrées requises pour les workflows DetectXpert et garantit leur conformité aux formats attendus.

## 📑 Sommaire

- [À propos](#-à-propos)
- [Prérequis](#-prérequis)
- [Utilisation](#-utilisation)
- [Inputs](#️-inputs)
- [Outputs](#-outputs)
- [Codes de sortie](#-codes-de-sortie)
- [Versioning et Stabilité](#-versioning-et-stabilité)
- [Tests](#-tests)
- [Tests de non-régression](#-tests-de-non-régression)
- [Mainteneurs et Support](#-mainteneurs-et-support)
- [Licence](#-licence)

## 🔍 À propos

L'action `validate_inputs` effectue une série de validations sur les paramètres d'entrée fournis aux workflows DetectXpert. Elle vérifie que tous les paramètres respectent les formats et contraintes requis, puis génère des outputs structurés pour les étapes suivantes du workflow.

Pour plus de détails sur l'implémentation, consultez le [repository des actions DetectXpert](https://github.com/detectxpert/devops).

## 📋 Prérequis

- **Bash** (version ≥ 4.x)
- **jq** (obligatoire) - Utilisé pour le traitement JSON
- **Outils supplémentaires**: `grep`, `xargs`
- **Compatibilité**:
  - ✅ Ubuntu (testé sur Ubuntu 20.04 et 22.04)
  - ✅ macOS (testé sur 11 et 12)
  - ⚠️ Windows (nécessite Git Bash ou WSL)

## 🚀 Utilisation

### Exemple minimal

```yaml
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Valider les entrées
        id: validate
        uses: detectxpert/devops/.github/actions/validate_inputs@v1.1.0
        with:
          environment: production
          version: 2.1.0

      - name: Afficher le résultat
        run: |
          echo "Validation réussie: ${{ steps.validate.outputs.is_valid }}"
          echo "ID de déploiement: ${{ steps.validate.outputs.deployment_id }}"
```

### Exemple complet

yaml

```
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Valider les entrées
        id: validate
        uses: detectxpert/devops/.github/actions/validate_inputs@v1.1.0
        with:
          environment: production
          version: 2.1.0-alpha.5
          branch: feature/new-ui
          build_type: release
          product_flavor: premium
          deployment_target: all
          artifact_path: 'build/outputs'
          enabled_features: tomography,ar,ai
          rtk_support: true
          offline_mode_level: full
          skip_tests: false
          test_devices: 'pixel_6,iphone_13,samsung_s22'
          code_coverage_threshold: 85
          map_provider: mapbox
          analytics_enabled: true
          performance_profile: performance
          security_level: high
          encryption_enabled: true
          debug: false

      # Vérifier la validité
      - name: Vérifier la validation
        if: steps.validate.outputs.is_valid != 'true'
        run: |
          echo "❌ Validation échouée!"
          echo "Erreurs: ${{ steps.validate.outputs.validation_errors }}"
          exit 1

      # Utiliser la matrice générée
      - name: Afficher la matrice de build
        run: echo '${{ steps.validate.outputs.build_matrix }}'

      # Continuer avec la matrice pour les builds parallèles
      - name: Créer la matrice pour le job suivant
        id: set-matrix
        if: steps.validate.outputs.is_valid == 'true'
        run: echo "matrix=${{ steps.validate.outputs.build_matrix }}" >> $GITHUB_OUTPUT
```

⚙️ Inputs
---------

### Configuration et déploiement

| Nom | Type | Requis | Défaut | Description | Validation |
| --- | --- | --- | --- | --- | --- |
| `debug` | boolean | Non | `false` | Active le mode debug avec logs détaillés | `true`, `false` |
| `environment` | string | Oui | `development` | Environnement de déploiement | `development`, `staging`, `production` |
| `version` | string | Oui | - | Version à déployer ([format SemVer](https://semver.org/)) | Format x.y.z[-suffix][+build] |
| `branch` | string | Non | `main` | Branche source pour le déploiement | Caractères alphanumériques, `_`, `.`, `-`, `/` |

### Paramètres de build

| Nom | Type | Requis | Défaut | Description | Validation |
| --- | --- | --- | --- | --- | --- |
| `build_type` | string | Non | `debug` | Type de build | `debug`, `release` |
| `product_flavor` | string | Non | `freemium` | Variante du produit | `freemium`, `premium`, `professional` |
| `deployment_target` | string | Non | `android` | Cible de déploiement | `android`, `ios`, `web`, `desktop`, `all` |
| `artifact_path` | string | Non | `build/outputs` | Chemin de stockage des artéfacts | Chemin relatif sans `/` initial ni caractères spéciaux comme `$` |

### Fonctionnalités et capacités

| Nom | Type | Requis | Défaut | Description | Validation |
| --- | --- | --- | --- | --- | --- |
| `enabled_features` | string | Non | `ai` | Fonctionnalités à activer | `all` ou liste séparée par virgules: `tomography`, `ar`, `multimodal`, `quantum`, `ai` |
| `rtk_support` | boolean | Non | `false` | Support RTK pour localisation précise | `true`, `false` |
| `offline_mode_level` | string | Non | `basic` | Niveau de support hors ligne | `basic`, `advanced`, `full` |

### Tests et qualité

| Nom | Type | Requis | Défaut | Description | Validation |
| --- | --- | --- | --- | --- | --- |
| `skip_tests` | boolean | Non | `false` | Sauter les tests | `true`, `false` |
| `test_devices` | string | Non | `default` | Liste d'appareils pour les tests | Liste séparée par virgules |
| `code_coverage_threshold` | number | Non | `70` | Seuil de couverture de code | 0-100 |

### Intégrations et sécurité

| Nom | Type | Requis | Défaut | Description | Validation |
| --- | --- | --- | --- | --- | --- |
| `api_key` | string | Non | - | Clé API pour services externes | Utiliser avec `${{ secrets.API_KEY }}` |
| `map_provider` | string | Non | `osm` | Fournisseur de cartes | `google`, `mapbox`, `osm` |
| `analytics_enabled` | boolean | Non | `false` | Activer l'analyse et le suivi | `true`, `false` |
| `performance_profile` | string | Non | `balanced` | Profil de performance | `balanced`, `performance`, `battery` |
| `security_level` | string | Non | `standard` | Niveau de sécurité | `standard`, `high`, `extreme` |
| `encryption_enabled` | boolean | Non | `false` | Activer le chiffrement | `true`, `false` |

📤 Outputs
----------

| Nom | Type | Description |
| --- | --- | --- |
| `is_valid` | boolean | Indique si toutes les entrées sont valides |
| `validation_errors` | JSON array | Liste des erreurs de validation rencontrées |
| `normalized_version` | string | Version normalisée au format semver |
| `deployment_id` | string | Identifiant unique généré pour ce déploiement |
| `build_matrix` | JSON object | Matrice de builds à exécuter basée sur les paramètres |
| `feature_flags` | JSON object | Configuration des feature flags pour ce déploiement |
| `estimated_build_time` | number | Temps estimé pour le processus de build complet (en minutes) |
| `skip_matrix` | boolean | Indique si la génération de matrice doit être ignorée |
| `validation_summary` | JSON object | Résumé des validations effectuées |

### Structure JSON des outputs

#### `validation_errors`

json

```
[
  "Environnement invalide: local. Valeurs autorisées: development, staging, production",
  "Version invalide: 1. Format requis: x.y.z[-suffix][+build]"
]
```

#### `build_matrix`

json

```
{
  "include": [
    {
      "target": "android",
      "flavor": "premium",
      "build_type": "release",
      "api_levels": ["29", "30", "31", "32", "33"],
      "arch": ["arm64-v8a", "armeabi-v7a"]
    },
    {
      "target": "ios",
      "flavor": "premium",
      "build_type": "release",
      "ios_version": ["14.0", "15.0", "16.0"],
      "device": ["iphone", "ipad"]
    }
  ]
}
```

#### `feature_flags`

json

```
{
  "tomography": true,
  "ar": true,
  "multimodal": false,
  "quantum": false,
  "ai": true
}
```

#### `validation_summary`

json

```
{
  "environment": "production",
  "version": "2.1.0-alpha.5",
  "deployment_id": "production-20230515123456-12345678",
  "estimated_time": 45,
  "targets": ["android", "ios", "web", "desktop"]
}
```

🚦 Codes de sortie
------------------

-   `exit 0` avec `is_valid=true` : Toutes les validations ont réussi
-   `exit 0` avec `is_valid=false` : Des erreurs de validation ont été détectées (détails dans `validation_errors`)
-   `exit 1` : Problème critique dans l'exécution de l'action (dépendance manquante, erreur de script)

🔒 Versioning et Stabilité
--------------------------

Il est fortement recommandé de pinner l'action à une version spécifique pour éviter les ruptures de compatibilité:

yaml

```
uses: detectxpert/devops/.github/actions/validate_inputs@v1.1.0
```

Les mises à jour de versions mineures (v1.1, v1.2) n'introduiront que des changements non cassants, tandis que les changements majeurs (v2, v3) peuvent modifier les interfaces et comportements.

🧪 Tests
--------

Pour tester l'action localement avant de la pousser, vous pouvez utiliser [act](https://github.com/nektos/act) ([Installation](https://github.com/nektos/act#installation)):

bash

```
# Test avec des paramètres valides
act -j validate_inputs -P ubuntu-latest -e tests/valid_inputs.json

# Test avec des paramètres invalides
act -j validate_inputs -P ubuntu-latest -e tests/invalid_inputs.json
```

🔄 Tests de non-régression
--------------------------

Pour s'assurer de la stabilité de l'action, un workflow de test pourrait être configuré comme suit:

yaml

```
name: Test validate_inputs Action

on:
  push:
    paths:
      - '.github/actions/validate_inputs/**'
  pull_request:
    paths:
      - '.github/actions/validate_inputs/**'

jobs:
  test-valid-inputs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Test avec inputs valides
        id: test-valid
        uses: ./.github/actions/validate_inputs
        with:
          environment: production
          version: 2.1.0
      - name: Vérifier la validation
        run: |
          [[ "${{ steps.test-valid.outputs.is_valid }}" == "true" ]] || exit 1

  test-invalid-inputs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Test avec inputs invalides
        id: test-invalid
        uses: ./.github/actions/validate_inputs
        with:
          environment: invalid
          version: 1
        continue-on-error: true
      - name: Vérifier les erreurs
        run: |
          [[ "${{ steps.test-invalid.outputs.is_valid }}" == "false" ]] || exit 1
          [[ $(echo '${{ steps.test-invalid.outputs.validation_errors }}' | jq length) -eq 2 ]] || exit 1
```

👥 Mainteneurs et Support
-------------------------

-   **Équipe mainteneuse**: DevOps Team DetectXpert
-   **Support**: Pour toute question ou problème, contacter l'équipe DevOps via Slack (#devops-support)
-   **Contributions**: Les pull requests sont les bienvenues selon notre processus interne

📄 Licence
----------

Propriétaire DetectXpert © 2025 - Tous droits réservés