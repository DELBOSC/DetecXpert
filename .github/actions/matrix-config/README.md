<!-- Badges -->

[![Build Status](https://img.shields.io/github/actions/workflow/status/your-org/detectxpert/matrix-config.yml)](https://github.com/your-org/detectxpert/actions)
[![Coverage Status](https://img.shields.io/codecov/c/github/your-org/detectxpert)](https://codecov.io/gh/your-org/detectxpert)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](/LICENSE)

<!-- Cover image -->

![Diagramme de la matrice](docs/images/matrix-diagram.png)

# Matrix Configuration Generator

*Action GitHub pour générer dynamiquement des matrices CI/CD pour DetectXpert.*

## Table des matières

* [Aperçu](#aperçu)
* [Prérequis](#prérequis)
* [Fonctionnalités](#fonctionnalités)
* [Utilisation](#utilisation)

  * [Exemple minimal](#exemple-minimal)
  * [Exemple de sortie générée](#exemple-de-sortie-générée)
  * [Exemple avancé](#exemple-avancé)
* [Paramètres](#paramètres)

  * [Généraux](#paramètres-généraux)
  * [Versions d’OS](#versions-dos)
  * [Flavors et dimensions](#flavors-et-dimensions)
* [Outputs](#outputs)
* [Notes techniques](#notes-techniques)
* [FAQ et astuces](#faq-et-astuces)
* [Développement](#développement)
* [Licence](#licence)

---

## Aperçu

Cette action GitHub génère une configuration de matrice dynamique pour les workflows CI/CD de DetectXpert. Elle permet de combiner différentes plateformes, versions d’OS, flavors et dimensions personnalisées en quelques lignes de YAML.

## Prérequis

* GitHub Actions runner avec **jq** v1.6+ installé
* Compatible : **Linux**, **macOS** et **Windows** (via Git Bash)

## Fonctionnalités

* Génère des matrices pour **Android**, **iOS**, **web** et **desktop**
* Valeurs par défaut intelligentes pour les versions d’OS
* Support des **flavors** (free, premium, professional)
* Dimensions personnalisables pour des matrices complexes
* Exclusion de combinaisons spécifiques
* Mode **debug** pour faciliter le diagnostic

## Utilisation

### Exemple minimal

```yaml
jobs:
  matrix-config:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v3
      - id: matrix
        uses: ./.github/actions/matrix-config
        with:
          platforms: android,ios

  build:
    needs: matrix-config
    strategy:
      matrix: ${{ fromJson(needs.matrix-config.outputs.matrix) }}
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "Building for ${{ matrix.platform }} with OS version ${{ matrix.os-version }}"
```

### Exemple de sortie générée

```json
{
  "include": [
    { "platform": "android", "os-version": "24", "flavor": "free",    "path-prefix": "/build" },
    { "platform": "android", "os-version": "24", "flavor": "premium", "path-prefix": "/build" },
    { "platform": "ios",     "os-version": "14", "flavor": "free",   "path-prefix": "/build" }
    // ... autres combinaisons
  ]
}
```

### Exemple avancé

```yaml
jobs:
  matrix-config:
    runs-on: ubuntu-latest
    outputs:
      matrix:             ${{ steps.matrix.outputs.matrix }}
      matrix-include:     ${{ steps.matrix.outputs.matrix-include }}
      matrix-exclude:     ${{ steps.matrix.outputs.matrix-exclude }}
      total-combinations: ${{ steps.matrix.outputs.total-combinations }}
    steps:
      - uses: actions/checkout@v3
      - id: matrix
        uses: ./.github/actions/matrix-config
        with:
          config-type: test
          platforms: android,ios,web
          os-versions: android:24,29,33;ios:14,15,16;web:latest
          include-flavors: true
          flavors: free,premium,professional
          include-dimensions: true
          dimensions: |
            [
              { "name": "arch",   "values": ["arm64","x86_64"] },
              { "name": "locale", "values": ["fr","en","es"] }
            ]
          exclude-patterns: |
            [
              {"platform":"web","arch":"arm64"},
              {"platform":"ios","api-level":"24"},
              {"platform":"android","flavor":"free","locale":"es"}
            ]
          path-prefix: /artifacts/test
          debug: true
```

## Paramètres

### Paramètres généraux

| Paramètre   | Description                             | Type (req.)         | Défaut                  |
| ----------- | --------------------------------------- | ------------------- | ----------------------- |
| config-type | Type de config. (build, test, deploy)   | string (requis)     | build                   |
| platforms   | Plateformes (séparées par des virgules) | string (optionnel)  | android,ios,web,desktop |
| path-prefix | Préfixe de chemin pour les artefacts    | string (optionnel)  | `/build`                |
| debug       | Activer le mode debug                   | boolean (optionnel) | false                   |

### Versions d’OS

| Paramètre    | Description                                      | Type (optionnel) | Défaut                    |
| ------------ | ------------------------------------------------ | ---------------- | ------------------------- |
| os-versions  | Format `platform:versions;…`                     | string           | vide (valeurs par défaut) |
| api-levels   | Niveaux d’API Android (séparés par des virgules) | string           | 24,26,29,31,33            |
| ios-versions | Versions iOS (séparées par des virgules)         | string           | 14,15,16                  |

**Format `os-versions`** :

```
android:24,26,29;ios:14,15,16;web:latest;desktop:latest
```

**Valeurs par défaut appliquées** :

* Android : 24,26,29,31,33
* iOS : 14,15,16
* Web & Desktop : `latest`

### Flavors et dimensions

| Paramètre          | Description                                  | Type (optionnel) | Défaut                    |
| ------------------ | -------------------------------------------- | ---------------- | ------------------------- |
| include-flavors    | Inclure les flavors                          | boolean          | true                      |
| flavors            | Liste des flavors (séparés par des virgules) | string           | free,premium,professional |
| include-dimensions | Inclure des dimensions supplémentaires       | boolean          | false                     |
| dimensions         | JSON d’axes supplémentaires                  | string           | `[]`                      |
| exclude-patterns   | JSON de motifs d’exclusion                   | string           | `[]`                      |

**Exemple de `dimensions`** :

```json
[
  { "name": "arch",  "values": ["arm64","x86_64"] },
  { "name": "mode",  "values": ["debug","release"] }
]
```

**Exemple de `exclude-patterns`** :

```json
[
  {"platform":"web","arch":"arm64"},
  {"platform":"ios","flavor":"free","locale":"fr"}
]
```

## Outputs

| Output               | Description                            |
| -------------------- | -------------------------------------- |
| `matrix`             | JSON à utiliser dans `strategy.matrix` |
| `matrix-include`     | Combinaisons à inclure (optionnel)     |
| `matrix-exclude`     | Combinaisons à exclure (optionnel)     |
| `total-combinations` | Nombre total de combinaisons           |

## Notes techniques

* Si aucune combinaison n’est générée (exclusions trop strictes), une matrice minimale est produite :

  * première plateforme spécifiée
  * OS version `latest`
  * `path-prefix` spécifié
* Un avertissement est affiché en log en mode **debug**.
* Sur Windows : assurez-vous que **jq** est dans le `PATH`.

## FAQ et astuces

**Q : Comment limiter le nombre de combinaisons ?**

* Limitez les plateformes
* Réduisez les versions d’OS
* Désactivez les flavors
* Utilisez `exclude-patterns` ciblés

**Q : Comment déboguer sur Windows ?**

* Installez `jq` et utilisez Git Bash
* Activez le mode debug
* Préférez `/` comme séparateur de chemins

**Q : Comment personnaliser les clés JSON de sortie ?**
Utilisez `actions/github-script` pour transformer la sortie, par ex. :

```yaml
- uses: actions/github-script@v6
  id: transform
  with:
    script: |
      const m = JSON.parse(process.env.MATRIX);
      return JSON.stringify({
        include: m.include.map(i => ({ target: i.platform, version: i['os-version'] }))
      });
    result-encoding: string
```

## Développement

* **Source** : `.github/actions/matrix-config/action.yml`
* **Script** : `.github/actions/matrix-config/matrix-config.sh`
* **Tests** : `.github/actions/matrix-config/tests/`

### Exécuter les tests

```bash
cd .github/actions/matrix-config/tests
bats .
```

## Licence

MIT
