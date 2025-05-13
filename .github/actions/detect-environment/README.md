📦 Detect Environment Action
============================

**Version** : 1.0.0

**Politique de versioning** :

-   **1.x** : ajouts / corrections non-cassants
-   **2.0+** : changements majeurs

🚀 Utilisation
--------------

### Exemple minimal

yaml

```
- uses: detectxpert/devops/.github/actions/detect-environment@v1.0.0
```

### Exemple avancé

yaml

```
- id: env-info
  uses: detectxpert/devops/.github/actions/detect-environment@v1.0.0
  with:
    debug: true
    output_format: yaml
    detect_network: true
    required_dependencies: jq,grep,curl,git
    performance_test: true
```

### Récupération des outputs

yaml

```
- id: env-info
  uses: detectxpert/devops/.github/actions/detect-environment@v1.0.0

- name: Afficher les informations
  run: |
    echo "OS: ${{ steps.env-info.outputs.os_info }}"
    echo "Validité: ${{ steps.env-info.outputs.is_valid }}"
    echo "Résumé: ${{ steps.env-info.outputs.summary }}"
```

📥 Inputs
---------

| Nom | Type | Défaut | Description |
| --- | --- | --- | --- |
| `debug` | boolean | `false` | Active le mode debug avec logs détaillés |
| `verify_dependencies` | boolean | `true` | Vérifie la présence de `jq`, `grep`, `xargs` |
| `output_format` | string | `json` | Format de sortie (`json` | `yaml` | `text`) |
| `detect_hardware` | boolean | `true` | Génère `hardware_info` avec infos CPU/mémoire |
| `detect_network` | boolean | `false` | Génère `network_info` avec données de connectivité |
| `detect_dependencies` | boolean | `true` | Génère `software_info` avec versions logicielles |
| `detect_github_context` | boolean | `true` | Génère `github_context` avec infos GitHub Actions |
| `required_dependencies` | string | `jq,grep,xargs` | Liste des dépendances à vérifier |
| `performance_test` | boolean | `false` | Effectue des tests de performance (CPU/disque) |

📤 Outputs
----------

| Nom | Description |
| --- | --- |
| `os_info` | Infos système (OS, version, distro) |
| `hardware_info` | Infos matériel (CPU, mémoire, disque) |
| `software_info` | Versions des dépendances logicielles |
| `github_context` | Contexte GitHub Actions |
| `network_info` | Données de connectivité réseau |
| `performance_metrics` | Métriques de performance (si `performance_test=true`) |
| `is_valid` | Booléen indiquant si l'environnement est valide |
| `validation_errors` | Liste des problèmes détectés |
| `environment_id` | Identifiant unique de l'environnement |
| `summary` | Résumé des informations essentielles |

🎨 Formats de sortie
--------------------

### JSON (défaut)

json

```
{
  "cpu": {
    "cores": 4,
    "model": "Intel® Core™ i7",
    "architecture": "x86_64"
  },
  "memory": {
    "total": "16GB",
    "available": "12GB"
  }
}
```

### YAML

yaml

```
cpu:
  cores: 4
  model: "Intel® Core™ i7"
  architecture: "x86_64"
memory:
  total: "16GB"
  available: "12GB"
```

### TEXT

```
CPU: 4 cores (Intel® Core™ i7), Architecture: x86_64
Memory: 16GB total, 12GB available
```

🛠 Script principal
-------------------

bash

```
#!/usr/bin/env bash
set -euo pipefail

# Récupérer les inputs
OUTPUT_FORMAT="${DETECT_OUTPUT_FORMAT:-json}"
DEBUG="${DETECT_DEBUG:-false}"

# Validation du format
if [[ ! "$OUTPUT_FORMAT" =~ ^(json|yaml|text)$ ]]; then
  echo "::error::Format invalide: '$OUTPUT_FORMAT'. Autorisé: json, yaml, text"
  exit 1
fi

# Extraction des autres paramètres...

# Active debug
[[ "$DEBUG" == "true" ]] && set -x

# ...suite de l'implémentation...
```

*Voir le script complet dans* `.github/actions/detect-environment/detect_environment.sh`

🧪 CI & Tests
-------------

Nous utilisons Bats :

yaml

```
name: Test Detect Environment Action
on:
  [push, pull_request]
  paths:
    - '.github/actions/detect-environment/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm install -g bats
      - run: bats .github/actions/detect-environment/tests/test_detect_environment.bats

      - name: Test JSON
        id: json
        uses: ./.github/actions/detect-environment
        with:
          output_format: json

      - name: Vérifier JSON
        run: |
          echo "${{ steps.json.outputs.hardware_info }}" | jq .
```

*Voir* `.github/workflows/test-detect-environment.yml` *pour plus de détails.*

🤝 Contribution
---------------

1.  Forker ce dépôt
2.  Créer une branche feature/...
3.  Ajouter vos modifications & tests
4.  Ouvrir une Pull Request

📄 Licence
----------

MIT © DetectXpert DevOps Team