#!/usr/bin/env bash
# ----------------------------------------------------------------------
# Script de validation des entrées pour DetectXpert
# Valide les entrées requises pour les workflows et garantit leur conformité
# Version: 1.2.0
# ----------------------------------------------------------------------

# Variables globales
VERBOSITY=1 # 0=silencieux, 1=normal, 2=debug

# -----------------------------------------------------------------------------
# Configuration - Définitions des configurations et valeurs valides
# -----------------------------------------------------------------------------

# Configuration des plateformes (définie une seule fois pour optimisation)
readonly PLATFORM_CONFIGS='{
  "android": {
    "api_levels": ["29", "30", "31", "32", "33"],
    "arch": ["arm64-v8a", "armeabi-v7a"]
  },
  "ios": {
    "ios_version": ["14.0", "15.0", "16.0"],
    "device": ["iphone", "ipad"]
  },
  "web": {
    "browsers": ["chrome", "firefox", "safari"]
  },
  "desktop": {
    "os": ["windows", "macos", "linux"]
  }
}'

# Liste des fonctionnalités valides en JSON
readonly VALID_FEATURES_JSON='["tomography", "ar", "multimodal", "quantum", "ai"]'

# -----------------------------------------------------------------------------
# Trap pour erreurs inattendues
# -----------------------------------------------------------------------------

# Capture les erreurs inattendues pour les distinguer des erreurs de validation
trap 'echo "❌ ERREUR CRITIQUE: Une erreur inattendue s'\''est produite à la ligne ${LINENO}. Commande: ${BASH_COMMAND}" >&2; exit 1' ERR

# -----------------------------------------------------------------------------
# Fonctions de logging et d'utilitaires
# -----------------------------------------------------------------------------

# Affiche un message de débogage si le niveau de verbosité le permet
# @param $* Message de débogage à afficher
log_debug() {
  if [[ $VERBOSITY -ge 2 ]]; then
    echo "🔍 DEBUG: $*"
  fi
}

# Affiche un message d'information si le niveau de verbosité le permet
# @param $* Message d'information à afficher
log_info() {
  if [[ $VERBOSITY -ge 1 ]]; then
    echo "ℹ️ $*"
  fi
}

# Affiche un message d'erreur (toujours affiché, dirigé vers stderr)
# @param $* Message d'erreur à afficher
log_error() {
  echo "❌ $*" >&2
}

# Ajoute un message d'erreur au tableau des erreurs de validation
# @param $1 Message d'erreur à ajouter
add_error() {
  local error_message="$1"
  VALIDATION_ERRORS=$(jq --arg msg "$error_message" '. += [$msg]' <<< "$VALIDATION_ERRORS")
  ERROR_COUNT=$((ERROR_COUNT + 1))
  log_error "Erreur: $error_message"
}

# Écrit en toute sécurité dans le fichier de sortie GitHub, en gérant les valeurs multi-lignes
# @param $1 Nom de la variable de sortie
# @param $2 Valeur à écrire (peut contenir des sauts de ligne)
safe_output() {
  local name="$1"
  local value="$2"

  # Utiliser la syntaxe de délimiteur pour gérer correctement les newlines et caractères spéciaux
  # Génération d'un délimiteur unique sans dépendance à OpenSSL
  local delimiter="EOF_${SCRIPT_TIMESTAMP}_$$"
  
  {
    echo "$name<<$delimiter"
    echo "$value"
    echo "$delimiter"
  } >> "$GITHUB_OUTPUT"

  if [ $? -ne 0 ]; then
    log_error "Échec de l'écriture de la sortie '$name'"
    return 1
  fi
  return 0
}

# Valide que la chaîne JSON est valide
# @param $1 JSON à valider
# @param $2 Nom du champ (pour les messages d'erreur)
# @return 0 si JSON valide, 1 sinon
validate_json() {
  local json="$1"
  local field_name="$2"
  
  if ! jq empty <<< "$json" 2>/dev/null; then
    log_error "JSON invalide généré pour $field_name"
    return 1
  fi
  return 0
}

# Convertit un tableau bash en JSON de manière sécurisée
# @param $1+ Éléments du tableau à convertir
# @return JSON du tableau via echo
bash_array_to_json() {
  # Version sécurisée avec jq pour échapper correctement les caractères spéciaux
  printf '%s\n' "$@" | jq -R . | jq -s .
}

# -----------------------------------------------------------------------------
# Fonctions d'initialisation et de vérification
# -----------------------------------------------------------------------------

# Vérifie qu'une dépendance est disponible dans le système
# @param $1 Nom de la commande à vérifier
# @return 0 si disponible, exit 1 sinon
check_dependency() {
  command -v "$1" >/dev/null 2>&1 || { 
    log_error "$1 est requis mais n'est pas installé sur ce runner."
    log_error "Veuillez l'installer ou utiliser un runner avec $1 préinstallé."
    exit 1
  }
}

# Initialise l'environnement et vérifie les prérequis
# @return 0 si succès, exit 1 sinon
init() {
  set -euo pipefail
  IFS=$'\n\t'
  
  # Vérification Bash
  if [ -z "${BASH_VERSION-}" ]; then
    log_error "Veuillez exécuter ce script avec bash, pas sh ou un autre shell."
    exit 1
  fi
  
  # Vérification des dépendances
  for dep in jq grep xargs; do
    check_dependency "$dep"
  done
  
  # Vérification des variables d'environnement requises
  : "${GITHUB_OUTPUT:?Variable GITHUB_OUTPUT est requise}"
  
  # Gestion unifiée des valeurs par défaut
  # Note: Ces valeurs sont normalement définies dans action.yml, 
  # mais nous ajoutons une couche de sécurité ici
  : "${INPUT_ENVIRONMENT:=development}"
  : "${INPUT_VERSION:=0.1.0}"
  : "${INPUT_BUILD_TYPE:=debug}"
  : "${INPUT_PRODUCT_FLAVOR:=freemium}"
  : "${INPUT_DEPLOYMENT_TARGET:=android}"
  : "${INPUT_ENABLED_FEATURES:=ai}"
  : "${INPUT_OFFLINE_MODE_LEVEL:=basic}"
  : "${INPUT_RTK_SUPPORT:=false}"
  : "${INPUT_SKIP_TESTS:=false}"
  : "${INPUT_TEST_DEVICES:=default}"
  : "${INPUT_CODE_COVERAGE_THRESHOLD:=70}"
  : "${INPUT_MAP_PROVIDER:=osm}"
  : "${INPUT_ANALYTICS_ENABLED:=false}"
  : "${INPUT_PERFORMANCE_PROFILE:=balanced}"
  : "${INPUT_SECURITY_LEVEL:=standard}"
  : "${INPUT_ENCRYPTION_ENABLED:=false}"
  : "${INPUT_ARTIFACT_PATH:=build/outputs}"
  : "${INPUT_BRANCH:=main}"
  
  # Initialiser les variables globales
  ERROR_COUNT=0
  VALIDATION_ERRORS="[]"
  
  # Définir les valeurs valides (globales)
  declare -g VALID_ENVIRONMENTS=("development" "staging" "production")
  declare -g VALID_BUILD_TYPES=("debug" "release")
  declare -g VALID_FLAVORS=("freemium" "premium" "professional")
  declare -g VALID_TARGETS=("android" "ios" "web" "desktop" "all")
  declare -g VALID_FEATURES=("tomography" "ar" "multimodal" "quantum" "ai")
  declare -g VALID_OFFLINE_LEVELS=("basic" "advanced" "full")
  declare -g VALID_MAP_PROVIDERS=("google" "mapbox" "osm")
  declare -g VALID_PERFORMANCE_PROFILES=("balanced" "performance" "battery")
  declare -g VALID_SECURITY_LEVELS=("standard" "high" "extreme")
  
  log_info "Initialisation de la validation..."
}

# Affiche les valeurs d'entrée en mode debug
log_input_values() {
  if [[ $VERBOSITY -ge 2 ]]; then
    log_debug "Valeurs d'entrée:"
    log_debug "  ENVIRONMENT: $INPUT_ENVIRONMENT"
    log_debug "  VERSION: $INPUT_VERSION"
    log_debug "  BUILD_TYPE: $INPUT_BUILD_TYPE"
    log_debug "  PRODUCT_FLAVOR: $INPUT_PRODUCT_FLAVOR"
    log_debug "  DEPLOYMENT_TARGET: $INPUT_DEPLOYMENT_TARGET"
    log_debug "  ENABLED_FEATURES: $INPUT_ENABLED_FEATURES"
    log_debug "  OFFLINE_MODE_LEVEL: $INPUT_OFFLINE_MODE_LEVEL"
    log_debug "  RTK_SUPPORT: $INPUT_RTK_SUPPORT"
    log_debug "  SKIP_TESTS: $INPUT_SKIP_TESTS"
    log_debug "  TEST_DEVICES: $INPUT_TEST_DEVICES"
    log_debug "  CODE_COVERAGE_THRESHOLD: $INPUT_CODE_COVERAGE_THRESHOLD"
    log_debug "  MAP_PROVIDER: $INPUT_MAP_PROVIDER"
    log_debug "  ANALYTICS_ENABLED: $INPUT_ANALYTICS_ENABLED"
    log_debug "  PERFORMANCE_PROFILE: $INPUT_PERFORMANCE_PROFILE"
    log_debug "  SECURITY_LEVEL: $INPUT_SECURITY_LEVEL"
    log_debug "  ENCRYPTION_ENABLED: $INPUT_ENCRYPTION_ENABLED"
    log_debug "  ARTIFACT_PATH: $INPUT_ARTIFACT_PATH"
    log_debug "  BRANCH: $INPUT_BRANCH"
  fi
}

# -----------------------------------------------------------------------------
# Fonctions de validation
# -----------------------------------------------------------------------------

# Valide une valeur par rapport à une liste de valeurs acceptables
# @param $1 Valeur à valider
# @param $2 Nom de l'input (pour les messages d'erreur)
# @param $3+ Liste des valeurs valides
# @return 0 si valide, 1 si invalide
validate_enum() {
  local input_value="$1"
  local input_name="$2"
  shift 2
  local valid_values=("$@")
  
  log_debug "Validation de $input_name: '$input_value'"
  
  local is_valid=false
  for valid_value in "${valid_values[@]}"; do
    if [[ "$input_value" == "$valid_value" ]]; then
      is_valid=true
      break
    fi
  done
  
  if [[ "$is_valid" != "true" ]]; then
    add_error "$input_name invalide: $input_value. Valeurs autorisées: ${valid_values[*]}"
    return 1
  fi
  
  return 0
}

# Valide une valeur booléenne
# @param $1 Valeur à valider
# @param $2 Nom de l'input (pour les messages d'erreur)
# @return 0 si valide, 1 si invalide
validate_boolean() {
  local input_value="$1"
  local input_name="$2"
  
  log_debug "Validation booléenne de $input_name: '$input_value'"
  
  if [[ ! "$input_value" =~ ^(true|false)$ ]]; then
    add_error "$input_name invalide: $input_value. Valeurs autorisées: true, false"
    return 1
  fi
  
  return 0
}

# Valide une version selon la spécification SemVer
# @param $1 Version à valider
# @return 0 si valide, 1 si invalide
validate_semver() {
  local version="$1"
  log_debug "Validation de la version SemVer: $version"
  
  # Regex SemVer complète
  if [[ ! $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]; then
    add_error "Version invalide: $version. Format requis: x.y.z[-suffix][+build]"
    return 1
  else
    NORMALIZED_VERSION="$version"
    log_info "✅ Version valide: $NORMALIZED_VERSION"
    return 0
  fi
}

# Valide le seuil de couverture de code
# @param $1 Seuil à valider
# @return 0 si valide, 1 si invalide
validate_code_coverage() {
  local coverage="$INPUT_CODE_COVERAGE_THRESHOLD"
  log_debug "Validation du seuil de couverture: $coverage"
  
  if ! [[ "$coverage" =~ ^[0-9]+$ ]] || [ "$coverage" -lt 0 ] || [ "$coverage" -gt 100 ]; then
    add_error "Seuil de couverture de code invalide: $coverage. Doit être un entier entre 0 et 100."
    return 1
  fi
  return 0
}

# Valide les appareils de test
# @return 0 si valide, 1 si invalide
validate_test_devices() {
  local devices="$INPUT_TEST_DEVICES"
  log_debug "Validation des appareils de test: $devices"
  
  if [[ -z "$devices" ]]; then
    add_error "La liste des appareils de test ne peut pas être vide. Utilisez au moins 'default'."
    return 1
  fi
  return 0
}

# Valide le chemin des artefacts
# @return 0 si valide, 1 si invalide
validate_artifact_path() {
  local path="$INPUT_ARTIFACT_PATH"
  log_debug "Validation du chemin d'artefact: $path"
  
  # Vérifier la présence de caractères spéciaux potentiellement problématiques
  if [[ "$path" =~ :[/\\] ]] || [[ "$path" =~ ^[/\\] ]] || [[ "$path" =~ ['$'] ]]; then
    add_error "Chemin d'artefact invalide: $path. Utilisez un chemin relatif sans protocole ni caractères spéciaux."
    return 1
  fi
  return 0
}

# Valide le nom de branche
# @return 0 si valide, 1 si invalide
validate_branch() {
  local branch="$INPUT_BRANCH"
  log_debug "Validation du nom de branche: $branch"
  
  if [[ -n "$branch" ]] && ! [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    add_error "Nom de branche invalide: $branch. Utilisez uniquement des caractères alphanumériques, points, tirets et slashs."
    return 1
  fi
  return 0
}

# Valide les fonctionnalités activées et génère le JSON des feature flags
# Cette fonction combine validation et génération pour plus d'efficacité
# @return 0 si valide, 1 si invalide
validate_and_generate_features() {
  local features="$INPUT_ENABLED_FEATURES"
  log_debug "Validation et génération des fonctionnalités: $features"
  
  # Si "all", générer directement les feature flags sans validation
  if [[ "$features" == "all" ]]; then
    FEATURE_FLAGS=$(jq 'reduce .[] as $f ({}; . + {($f): true})' <<< "$VALID_FEATURES_JSON")
    return 0
  fi
  
  # Convertir la liste séparée par virgules en tableau JSON de manière sécurisée
  local requested_features_json
  requested_features_json=$(echo "$features" | tr ',' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')
  
  # Faire la validation et la génération en une seule opération jq
  local result
  result=$(jq -n \
    --argjson valid "$VALID_FEATURES_JSON" \
    --argjson requested "$requested_features_json" \
    '{
      "invalid": ($requested - $valid),
      "feature_flags": ($valid | reduce .[] as $f ({}; . + {($f): ($f | IN($requested))}))
    }')
  
  # Extraire les fonctionnalités invalides et les feature flags
  local invalid_features
  invalid_features=$(jq -r '.invalid | join(", ")' <<< "$result")
  
  if [[ -n "$invalid_features" && "$invalid_features" != "null" ]]; then
    add_error "Fonctionnalités invalides: $invalid_features. Valeurs autorisées: ${VALID_FEATURES[*]}"
    return 1
  fi
  
  # Stocker les feature flags
  FEATURE_FLAGS=$(jq '.feature_flags' <<< "$result")
  
  # Valider le JSON généré
  validate_json "$FEATURE_FLAGS" "feature_flags" || return 1
  
  log_debug "Feature flags générés: $FEATURE_FLAGS"
  return 0
}

# Valide tous les inputs
# @return 0 si tous valides, nombres d'erreurs détectées sinon
validate_inputs() {
  log_info "Validation des entrées..."
  
  # Valider l'environnement
  validate_enum "$INPUT_ENVIRONMENT" "Environnement" "${VALID_ENVIRONMENTS[@]}"
  
  # Valider la version SemVer
  validate_semver "$INPUT_VERSION"
  
  # Valider les paramètres énumérés
  validate_enum "$INPUT_BUILD_TYPE" "Type de build" "${VALID_BUILD_TYPES[@]}"
  validate_enum "$INPUT_PRODUCT_FLAVOR" "Product flavor" "${VALID_FLAVORS[@]}"
  validate_enum "$INPUT_DEPLOYMENT_TARGET" "Cible de déploiement" "${VALID_TARGETS[@]}"
  validate_enum "$INPUT_OFFLINE_MODE_LEVEL" "Niveau de mode hors ligne" "${VALID_OFFLINE_LEVELS[@]}"
  validate_enum "$INPUT_MAP_PROVIDER" "Fournisseur de cartes" "${VALID_MAP_PROVIDERS[@]}"
  validate_enum "$INPUT_PERFORMANCE_PROFILE" "Profil de performance" "${VALID_PERFORMANCE_PROFILES[@]}"
  validate_enum "$INPUT_SECURITY_LEVEL" "Niveau de sécurité" "${VALID_SECURITY_LEVELS[@]}"
  
  # Valider les booléens
  validate_boolean "$INPUT_RTK_SUPPORT" "RTK support"
  validate_boolean "$INPUT_SKIP_TESTS" "Skip tests"
  validate_boolean "$INPUT_ANALYTICS_ENABLED" "Analytics enabled"
  validate_boolean "$INPUT_ENCRYPTION_ENABLED" "Encryption enabled"
  
  # Valider et générer les fonctionnalités activées (combine validation et génération)
  validate_and_generate_features
  
  # Valider le seuil de couverture de code
  validate_code_coverage
  
  # Valider les appareils de test
  validate_test_devices
  
  # Valider le chemin des artefacts
  validate_artifact_path
  
  # Valider le nom de branche
  validate_branch
  
  return $ERROR_COUNT
}

# -----------------------------------------------------------------------------
# Fonctions de génération
# -----------------------------------------------------------------------------

# Génère la matrice de build selon les cibles de déploiement
# @return 0
generate_matrix() {
  log_info "Construction de la matrice de build..."
  
  # Définir les cibles de déploiement
  if [[ "$INPUT_DEPLOYMENT_TARGET" == "all" ]]; then
    TARGETS=("android" "ios" "web" "desktop")
  else
    TARGETS=("$INPUT_DEPLOYMENT_TARGET")
  fi
  
  # Création du JSON des cibles (optimisé et sécurisé)
  local targets_json
  targets_json=$(bash_array_to_json "${TARGETS[@]}")
  
  # Générer les items de matrice en une seule opération jq
  MATRIX_JSON=$(jq -n \
    --argjson platforms "$PLATFORM_CONFIGS" \
    --argjson targets "$targets_json" \
    --arg flavor "$INPUT_PRODUCT_FLAVOR" \
    --arg buildType "$INPUT_BUILD_TYPE" \
    '{
      include: $targets | map(
        . as $target | {
          target: $target,
          flavor: $flavor,
          build_type: $buildType
        } + ($platforms[$target] // {})
      )
    }')
  
  # Valider le JSON généré
  validate_json "$MATRIX_JSON" "build_matrix" || return 1
  
  log_debug "Matrice générée: $MATRIX_JSON"
  return 0
}

# Calcule le temps estimé pour le build
# @return 0
calculate_estimated_time() {
  # Compter directement le nombre de fonctionnalités activées avec jq
  local features_count
  features_count=$(jq 'map_values(select(. == true)) | length' <<< "$FEATURE_FLAGS")
  
  local base_time=10
  local feature_time=$((features_count * 5))
  
  local test_time=0
  if [[ "$INPUT_SKIP_TESTS" == "false" ]]; then
    test_time=15
  fi
  
  local platform_multiplier=1
  if [[ "$INPUT_DEPLOYMENT_TARGET" == "all" ]]; then
    platform_multiplier=4
  fi
  
  TOTAL_ESTIMATED_TIME=$(( (base_time + feature_time + test_time) * platform_multiplier ))
  
  log_info "⏱️ Temps estimé: $TOTAL_ESTIMATED_TIME minutes"
  return 0
}

# -----------------------------------------------------------------------------
# Fonctions d'output
# -----------------------------------------------------------------------------

# Génère et émet tous les outputs pour GitHub Actions
# @return 0
emit_outputs() {
  log_info "Génération des outputs..."
  
  # Utiliser UTC pour la génération de timestamp (cohérence entre plateformes)
  # Note: cette approche garantit des timestamps cohérents indépendamment 
  # du fuseau horaire du runner - l'ID de déploiement sera toujours en UTC
  DEPLOY_ID="${INPUT_ENVIRONMENT}-${SCRIPT_TIMESTAMP}-${GITHUB_RUN_ID:-$(date +%s)}"
  
  log_info "📋 ID de déploiement: $DEPLOY_ID (UTC)"
  
  # Calculer le temps estimé
  calculate_estimated_time
  
  # Créer le résumé de validation en une seule opération jq
  local targets_json
  targets_json=$(bash_array_to_json "${TARGETS[@]}")
  
  VALIDATION_SUMMARY=$(jq -n \
    --arg environment "$INPUT_ENVIRONMENT" \
    --arg version "$NORMALIZED_VERSION" \
    --arg deployment_id "$DEPLOY_ID" \
    --argjson estimated_time "$TOTAL_ESTIMATED_TIME" \
    --argjson targets "$targets_json" \
    '{
      environment: $environment,
      version: $version,
      deployment_id: $deployment_id,
      estimated_time: $estimated_time,
      targets: $targets
    }')
  
  # Valider le JSON généré
  validate_json "$VALIDATION_SUMMARY" "validation_summary" || return 1
  
  # Définir les outputs pour GitHub Actions - individuellement pour robustesse
  safe_output "is_valid" "$IS_VALID" || return 1
  safe_output "validation_errors" "$VALIDATION_ERRORS" || return 1
  safe_output "normalized_version" "$NORMALIZED_VERSION" || return 1
  safe_output "deployment_id" "$DEPLOY_ID" || return 1
  safe_output "estimated_build_time" "$TOTAL_ESTIMATED_TIME" || return 1
  safe_output "build_matrix" "$MATRIX_JSON" || return 1
  safe_output "feature_flags" "$FEATURE_FLAGS" || return 1
  safe_output "skip_matrix" "$SKIP_MATRIX" || return 1
  safe_output "validation_summary" "$VALIDATION_SUMMARY" || return 1
  
  return 0
}

# Génère un résumé textuel des résultats
# @return 0
print_summary() {
  if [ "$IS_VALID" = "true" ]; then
    # Obtenir les features activées
    local active_features
    active_features=$(jq -r 'to_entries | map(select(.value == true) | .key) | join(", ")' <<< "$FEATURE_FLAGS")
    
    # Obtenir les cibles formatées
    local targets_formatted
    if [ "${#TARGETS[@]}" -eq 1 ]; then
      targets_formatted="${TARGETS[0]}"
    else
      targets_formatted=$(printf "%s" "${TARGETS[@]}" | tr ' ' ',')
    fi
    
    # Afficher le résumé
    echo
    echo "┌──────────────────────────────────────────────────────────────────"
    echo "│ 🎯 RÉSUMÉ DE LA VALIDATION"
    echo "├──────────────────────────────────────────────────────────────────"
    echo "│ ✅ Succès de la validation"
    echo "│ 🌍 Environnement: $INPUT_ENVIRONMENT"
    echo "│ 📦 Version: $NORMALIZED_VERSION"
    echo "│ 📱 Cibles: $targets_formatted"
    echo "│ 🚀 Fonctionnalités: $active_features"
    echo "│ ⏱️  Temps estimé: $TOTAL_ESTIMATED_TIME minutes"
    echo "│ 🆔 ID de déploiement: $DEPLOY_ID"
    echo "└──────────────────────────────────────────────────────────────────"
  else
    echo
    echo "┌──────────────────────────────────────────────────────────────────"
    echo "│ ❌ ÉCHEC DE LA VALIDATION"
    echo "├──────────────────────────────────────────────────────────────────"
    echo "│ Nombre d'erreurs: $ERROR_COUNT"
    jq -r '.[]' <<< "$VALIDATION_ERRORS" | while read -r error_msg; do
      echo "│ • $error_msg"
    done
    echo "└──────────────────────────────────────────────────────────────────"
  fi
  
  return 0
}

# Fonction principale
# @return 0 en cas de succès ou d'erreurs de validation, 1 en cas d'erreur critique
main() {
  # Calculer un timestamp unique pour l'ensemble du script
  # Format UTC pour éviter les problèmes de fuseaux horaires
  SCRIPT_TIMESTAMP=$(TZ=UTC date +%Y%m%d%H%M%S)
  
  # Détecter si mode debug est activé (VALIDATE_INPUTS_DEBUG=1)
  if [[ "${VALIDATE_INPUTS_DEBUG:-0}" == "1" ]]; then
    VERBOSITY=2
    log_debug "Mode debug activé"
  elif [[ "${VALIDATE_INPUTS_QUIET:-0}" == "1" ]]; then
    VERBOSITY=0
    # Pas de log ici, mode silencieux
  fi
  
  # Initialisation
  init
  
  # Afficher les valeurs d'entrée en mode debug
  log_input_values
  
  # Valider les inputs
  validate_inputs
  
  # Déterminer si toutes les entrées sont valides
  if [ "$ERROR_COUNT" -gt 0 ]; then
    IS_VALID=false
    SKIP_MATRIX=true
    log_error "Des erreurs de validation ont été détectées. La génération de matrice sera ignorée."
    
    # Écrire les outputs de base pour un scénario d'échec
    safe_output "is_valid" "$IS_VALID"
    safe_output "validation_errors" "$VALIDATION_ERRORS"
    safe_output "skip_matrix" "$SKIP_MATRIX"
    
    # Afficher un résumé des erreurs
    print_summary
    
    log_info "Validation terminée : validation échouée, mais traitement normal (exit 0)"
    exit 0  # Validation KO mais comportement prévu (pas une erreur de script)
  else
    IS_VALID=true
    SKIP_MATRIX=false
    log_info "✅ Toutes les entrées sont valides."
    
    # Générer la matrice de build
    generate_matrix || {
      log_error "Échec de la génération de la matrice de build"
      exit 1
    }
    
    # Émettre tous les outputs
    emit_outputs || {
      log_error "Échec de l'émission des outputs"
      exit 1
    }
    
    # Afficher un résumé de la validation
    print_summary
    
    log_info "Validation terminée : validation réussie (exit 0)"
    exit 0  # Succès
  fi
}

# -----------------------------------------------------------------------------
# Pour les tests unitaires
# -----------------------------------------------------------------------------

# Si le script est exécuté directement (pas sourcé pour les tests)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

# Configuration pour bats-core
# Pour exécuter les tests: bats ./tests/validate_inputs.bats
# 
# Exemple de configuration CI pour tester le script:
# 
# name: Tests Unitaires Validate-Inputs
# on:
#   push:
#     paths:
#       - '.github/actions/validate-inputs/**'
#   pull_request:
#     paths:
#       - '.github/actions/validate-inputs/**'
# 
# jobs:
#   test:
#     runs-on: ubuntu-latest
#     steps:
#       - uses: actions/checkout@v3
#       - name: Install bats-core
#         run: |
#           git clone https://github.com/bats-core/bats-core.git
#           cd bats-core
#           ./install.sh $HOME
#       - name: Run tests
#         run: |
#           $HOME/bin/bats .github/actions/validate-inputs/tests/validate_inputs.bats
# 
# Exemple de tests complets dans tests/validate_inputs.bats:
# #!/usr/bin/env bats
#
# setup() {
#   source .github/actions/validate-inputs/validate-inputs.sh
#   export GITHUB_OUTPUT=$(mktemp)
# }
#
# teardown() {
#   rm -f "$GITHUB_OUTPUT"
# }
#
# @test "validate_enum avec valeur valide" {
#   run validate_enum "development" "Environnement" "development" "staging" "production"
#   [ "$status" -eq 0 ]
# }
#
# @test "validate_enum avec valeur invalide" {
#   run validate_enum "invalid" "Environnement" "development" "staging" "production"
#   [ "$status" -eq 1 ]
# }
#
# @test "validate_boolean avec true valide" {
#   run validate_boolean "true" "Flag"
#   [ "$status" -eq 0 ]
# }
#
# @test "validate_boolean avec valeur invalide" {
#   run validate_boolean "yes" "Flag"
#   [ "$status" -eq 1 ]
# }
#
# @test "validate_semver avec version valide" {
#   run validate_semver "1.2.3"
#   [ "$status" -eq 0 ]
# }
#
# @test "validate_semver avec version invalide" {
#   run validate_semver "1.2"
#   [ "$status" -eq 1 ]
# }
#
# @test "bash_array_to_json fonctionne correctement" {
#   result=$(bash_array_to_json "dev" "test" "prod")
#   [ "$(echo "$result" | jq -c '.')" = '["dev","test","prod"]' ]
# }
#
# @test "bash_array_to_json gère correctement les guillemets" {
#   result=$(bash_array_to_json 'value "with" quotes' 'normal value')
#   local expected='["value \"with\" quotes","normal value"]'
#   [ "$(echo "$result" | jq -c '.')" = "$expected" ]
# }
#
# @test "safe_output gère correctement les caractères spéciaux" {
#   safe_output "test_output" 'value with $pecial ch@racters and "quotes"'
#   grep -q 'value with \$pecial ch@racters and "quotes"' "$GITHUB_OUTPUT"
#   [ "$?" -eq 0 ]
# }
#
# @test "validate_artifact_path rejette les chemins avec $ comme variable shell" {
#   run validate_artifact_path
#   export INPUT_ARTIFACT_PATH="build/$VERSION"
#   [ "$status" -eq 1 ]
# }