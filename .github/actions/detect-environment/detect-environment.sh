#!/usr/bin/env bash

# detect-environment.sh
# Script pour détecter automatiquement l'environnement d'exécution dans les workflows GitHub Actions
# pour l'application DetectXpert
#
# Usage:
#   1. Placez ce script dans votre répertoire .github/actions/detect-environment
#   2. Assurez-vous qu'il est exécutable avec: chmod +x detect-environment.sh
#   3. Référencez-le dans votre fichier action.yml
#
# Variables d'entrée (définies via des variables d'environnement):
#   - OVERRIDE_ENVIRONMENT: Force un environnement spécifique (production, staging, development)
#   - OVERRIDE_CONFIG: Force un fichier de configuration spécifique
#     Valeurs autorisées: prod_config.json, stage_config.json, dev_config.json, custom_config.json
#   - IGNORE_TAGS: Si défini à "true", ignore la détection basée sur les tags
#   - DEBUG: Si défini à "true", affiche des informations de débogage supplémentaires
#   - LANGUAGE: Langue des messages (fr, en) - Par défaut: fr
#
# Version: 1.2.0

# Options de sécurité pour bash
set -euo pipefail

# Détermine le chemin absolu du répertoire contenant ce script
ACTION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Variables pour la gestion des erreurs
ERROR_COUNT=0
ERROR_MESSAGES=""

# Récupère la version depuis Git si disponible, sinon utilise une valeur par défaut
if command -v git &> /dev/null && git rev-parse --is-inside-work-tree &> /dev/null; then
  VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.2.0")
else
  VERSION="1.2.0"
fi

# Langue par défaut
LANGUAGE=${LANGUAGE:-fr}

# Chargement des messages localisés
# Si un fichier de messages existe, le charger
I18N_FILE="${ACTION_ROOT}/i18n_messages.${LANGUAGE}.env"
if [[ -f "$I18N_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$I18N_FILE"
else
  # Messages i18n intégrés (fallback)
  # FR
  MSG_ERR_GITHUB_OUTPUT_FR="Variable GITHUB_OUTPUT non définie—exécutez dans un contexte GitHub Actions"
  MSG_ERR_ENV_UNKNOWN_FR="Environnement non reconnu: %s"
  MSG_ERR_ENV_INVALID_FR="Environnement forcé non valide: %s. Valeurs autorisées: %s"
  MSG_ERR_CONFIG_INVALID_FR="Fichier de configuration forcé non valide: %s. Valeurs autorisées: %s"
  
  # EN
  MSG_ERR_GITHUB_OUTPUT_EN="GITHUB_OUTPUT variable not defined—run in a GitHub Actions context"
  MSG_ERR_ENV_UNKNOWN_EN="Unknown environment: %s"
  MSG_ERR_ENV_INVALID_EN="Invalid forced environment: %s. Allowed values: %s"
  MSG_ERR_CONFIG_INVALID_EN="Invalid forced configuration file: %s. Allowed values: %s"
fi

# Fonction pour obtenir un message localisé
get_message() {
  local message_key="$1"
  local lang="${LANGUAGE:-fr}"
  local var_name="${message_key}_${lang^^}"
  
  # Si la variable existe, l'utiliser
  if [[ -n "${!var_name:-}" ]]; then
    echo "${!var_name}"
  else
    # Sinon utiliser le français comme fallback
    local fallback_var="${message_key}_FR"
    echo "${!fallback_var:-Missing translation: $message_key}"
  fi
}

# Définition centralisée des configurations d'environnement
declare -A ENV_CONFIGS
# Format: [env_name]="deploy_env:is_production:is_staging:is_development:config_file:log_level:debug_mode:verbose_mode"
ENV_CONFIGS=(
  ["production"]="prod:true:false:false:prod_config.json:info:false:false"
  ["staging"]="stage:false:true:false:stage_config.json:debug:false:true"
  ["development"]="dev:false:false:true:dev_config.json:debug:true:true"
)

# Environnements valides (extraits de ENV_CONFIGS)
VALID_ENVIRONMENTS=("production" "staging" "development")

# Fichiers de configuration valides
VALID_CONFIGS=("prod_config.json" "stage_config.json" "dev_config.json" "custom_config.json")

# Fonctions d'aide pour la journalisation
log_info() {
  echo "::info::$1"
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "[INFO] $1" >&2
  fi
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "[DEBUG] $1" >&2
  fi
}

# Collecte les erreurs au lieu de quitter immédiatement
log_error() {
  echo "::error::$1"
  ERROR_MESSAGES+="- $1\n"
  ERROR_COUNT=$((ERROR_COUNT + 1))
}

# Fonction pour exporter des variables vers GitHub Actions
set_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
    
    # Masquer les valeurs potentiellement sensibles dans les logs
    local log_value="$2"
    if [[ "$1" == *"token"* || "$1" == *"secret"* || "$1" == *"password"* || "$1" == *"key"* ]]; then
      log_value="********"
    fi
    
    log_info "Variable $1 définie sur $log_value"
  else
    log_info "[LOCAL] Variable $1 serait définie sur $2"
  fi
}

# Fonction pour appliquer les paramètres d'environnement
apply_env_settings() {
  local env_name="$1"
  
  # Vérifier si l'environnement est valide
  local env_config=""
  env_config="${ENV_CONFIGS[$env_name]:-}"
  
  if [[ -z "$env_config" ]]; then
    log_error "$(printf "$(get_message MSG_ERR_ENV_UNKNOWN)" "$env_name")"
    return 1
  fi
  
  # Extraire les valeurs du format env_config
  IFS=':' read -r DEPLOY_ENV IS_PRODUCTION IS_STAGING IS_DEVELOPMENT CONFIG_FILE LOG_LEVEL DEBUG_MODE VERBOSE_MODE <<< "$env_config"
  ENVIRONMENT="$env_name"
  
  log_debug "Configuration appliquée pour l'environnement: $env_name"
  return 0
}

# Fonction pour détecter l'environnement basé sur une référence (branche ou tag)
detect_from_ref() {
  local ref_type="$1"
  local ref_value="$2"
  local env_name="development"
  
  if [[ "$ref_type" == "branch" ]]; then
    # Détection basée sur le nom de la branche
    if [[ "$ref_value" == "main" || "$ref_value" == "master" ]]; then
      env_name="production"
    elif [[ "$ref_value" == "staging" || "$ref_value" == "preprod" || "$ref_value" =~ ^release\/.+$ ]]; then
      env_name="staging"
    elif [[ "$ref_value" =~ ^develop$ || "$ref_value" =~ ^dev$ ]]; then
      env_name="development"
    fi
  elif [[ "$ref_type" == "tag" && "${IGNORE_TAGS:-}" != "true" ]]; then
    # Détection basée sur les tags
    if [[ "$ref_value" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ && ! "$ref_value" =~ -(rc|beta|alpha) ]]; then
      env_name="production"
    elif [[ "$ref_value" =~ -rc[0-9]+ ]]; then
      env_name="staging"
    elif [[ "$ref_value" =~ -beta[0-9]*$ || "$ref_value" =~ -alpha[0-9]*$ ]]; then
      env_name="development"
    fi
  elif [[ "$ref_type" == "pull" || "$ref_type" == "changes" ]]; then
    # Détection pour refs/pull/* et refs/changes/*
    env_name="development"  # Par défaut pour les PRs et changes
  fi
  
  # Retourner l'environnement détecté
  echo "$env_name"
}

# Vérifie si une valeur est dans un tableau
is_in_array() {
  local value="$1"
  shift
  local array=("$@")
  
  for item in "${array[@]}"; do
    if [[ "$item" == "$value" ]]; then
      return 0
    fi
  done
  return 1
}

# Affiche un résumé synthétique des erreurs
summarize_errors() {
  if [ $ERROR_COUNT -gt 0 ]; then
    echo -e "\n::error::$ERROR_COUNT erreurs détectées lors de la détection d'environnement:"
    echo -e "$ERROR_MESSAGES"
    return 1
  fi
  return 0
}

# Extraire le type de référence et sa valeur d'une référence Git complète
parse_git_ref() {
  local full_ref="$1"
  
  if [[ "$full_ref" =~ ^refs/tags/ ]]; then
    echo "tag ${full_ref#refs/tags/}"
  elif [[ "$full_ref" =~ ^refs/heads/ ]]; then
    echo "branch ${full_ref#refs/heads/}"
  elif [[ "$full_ref" =~ ^refs/pull/[0-9]+/merge$ ]]; then
    # Utiliser sed pour extraire le numéro de PR en une seule opération
    echo "pull $(echo "$full_ref" | sed -E 's|^refs/pull/([0-9]+)/merge$|\1|')"
  elif [[ "$full_ref" =~ ^refs/changes/ ]]; then
    echo "changes ${full_ref#refs/changes/}"
  else
    # Cas par défaut, traiter comme une branche
    echo "branch $full_ref"
  fi
}

# Traiter tous les overrides au même endroit
process_overrides() {
  # Traiter IGNORE_TAGS
  if [[ "${IGNORE_TAGS:-}" == "true" ]]; then
    log_info "Détection par tags désactivée via IGNORE_TAGS=true"
  fi

  # Traiter OVERRIDE_ENVIRONMENT
  if [[ -n "${OVERRIDE_ENVIRONMENT:-}" ]]; then
    if is_in_array "$OVERRIDE_ENVIRONMENT" "${VALID_ENVIRONMENTS[@]}"; then
      local previous_env="$ENVIRONMENT"
      log_info "Environnement forcé de $previous_env à $OVERRIDE_ENVIRONMENT via OVERRIDE_ENVIRONMENT"
      apply_env_settings "$OVERRIDE_ENVIRONMENT"
    else
      log_error "$(printf "$(get_message MSG_ERR_ENV_INVALID)" "$OVERRIDE_ENVIRONMENT" "${VALID_ENVIRONMENTS[*]}")"
    fi
  fi

  # Traiter OVERRIDE_CONFIG
  if [[ -n "${OVERRIDE_CONFIG:-}" ]]; then
    if is_in_array "$OVERRIDE_CONFIG" "${VALID_CONFIGS[@]}"; then
      local previous_config="$CONFIG_FILE"
      CONFIG_FILE="${OVERRIDE_CONFIG}"
      log_info "Fichier de configuration forcé de $previous_config à $CONFIG_FILE via OVERRIDE_CONFIG"
    else
      log_error "$(printf "$(get_message MSG_ERR_CONFIG_INVALID)" "$OVERRIDE_CONFIG" "${VALID_CONFIGS[*]}")"
    fi
  fi
}

# -- Début de l'exécution principale -- #

# Vérifie si on s'exécute dans GitHub Actions
if [ -z "${GITHUB_OUTPUT:-}" ]; then
  log_error "$(get_message MSG_ERR_GITHUB_OUTPUT)"
fi

# Récupération des informations du contexte GitHub
GITHUB_REF=${GITHUB_REF:-}
GITHUB_REF_NAME=${GITHUB_REF_NAME:-}
GITHUB_HEAD_REF=${GITHUB_HEAD_REF:-}
GITHUB_BASE_REF=${GITHUB_BASE_REF:-}
GITHUB_EVENT_NAME=${GITHUB_EVENT_NAME:-}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-}

log_info "Détection de l'environnement pour: Ref=$GITHUB_REF, RefName=$GITHUB_REF_NAME, Event=$GITHUB_EVENT_NAME"

# Détermination de la branche actuelle
if [[ -n "$GITHUB_HEAD_REF" ]]; then
  # En cas de pull request
  BRANCH="$GITHUB_HEAD_REF"
  log_debug "Utilisation de GITHUB_HEAD_REF pour une pull request: $BRANCH"
else
  # En cas de push ou autre événement
  BRANCH="$GITHUB_REF_NAME"
  log_debug "Utilisation de GITHUB_REF_NAME pour un événement standard: $BRANCH"
fi

log_info "Branche détectée: $BRANCH"

# Configuration par défaut depuis la branche
ENV_NAME=$(detect_from_ref "branch" "$BRANCH")
log_debug "Environnement détecté depuis la branche: $ENV_NAME"
apply_env_settings "$ENV_NAME"

# Détection basée sur la référence complète (prioritaire sur la branche simple)
if [[ -n "$GITHUB_REF" && "${IGNORE_TAGS:-}" != "true" ]]; then
  # Analyser le type de référence et sa valeur
  read -r REF_TYPE REF_VALUE < <(parse_git_ref "$GITHUB_REF")
  log_debug "Type de référence détecté: $REF_TYPE, Valeur: $REF_VALUE"
  
  if [[ "$REF_TYPE" != "branch" || "$REF_VALUE" != "$BRANCH" ]]; then
    # Si le type n'est pas "branch" ou si la valeur est différente de la branche déjà détectée
    REF_ENV_NAME=$(detect_from_ref "$REF_TYPE" "$REF_VALUE")
    
    if [[ -n "$REF_ENV_NAME" && "$REF_ENV_NAME" != "$ENV_NAME" ]]; then
      log_info "Environnement changé de $ENV_NAME à $REF_ENV_NAME en fonction de la référence $REF_TYPE"
      apply_env_settings "$REF_ENV_NAME"
    fi
  fi
fi

# Traiter tous les overrides de manière centralisée
process_overrides

# Exporter toutes les variables vers GitHub Actions
log_info "==== Export des variables d'environnement ===="
set_output "environment" "$ENVIRONMENT"
set_output "deploy_env" "$DEPLOY_ENV"
set_output "is_production" "$IS_PRODUCTION"
set_output "is_staging" "$IS_STAGING"
set_output "is_development" "$IS_DEVELOPMENT"
set_output "config_file" "$CONFIG_FILE"
set_output "log_level" "$LOG_LEVEL"
set_output "debug_mode" "$DEBUG_MODE"
set_output "verbose_mode" "$VERBOSE_MODE"
set_output "branch" "$BRANCH"
set_output "version" "$VERSION"

# Résumé
log_info "==== Environnement Détecté ===="
log_info "Environnement: $ENVIRONMENT"
log_info "Branche: $BRANCH"
log_info "Déploiement: $DEPLOY_ENV"
log_info "Fichier de config: $CONFIG_FILE"
log_info "Version: $VERSION"
log_info "============================"

# Vérification des erreurs accumulées et sortie
summarize_errors || exit 1

exit 0

# =================================================
# Documentation pour les tests unitaires
# =================================================
# Exemples de tests avec bats:
#
# #!/usr/bin/env bats
#
# setup() {
#   export GITHUB_OUTPUT="$BATS_TMPDIR/github-output-$$"
#   touch "$GITHUB_OUTPUT"
#   # Réinitialiser les variables d'environnement
#   unset GITHUB_REF GITHUB_REF_NAME GITHUB_HEAD_REF OVERRIDE_ENVIRONMENT OVERRIDE_CONFIG IGNORE_TAGS
# }
#
# teardown() {
#   rm -f "$GITHUB_OUTPUT"
# }
#
# get_output_value() {
#   local key="$1"
#   grep "^$key=" "$GITHUB_OUTPUT" | cut -d= -f2
# }
#
# # Tests des branches
# @test "la branche main est détectée comme production" {
#   export GITHUB_REF_NAME="main"
#   run bash ./detect-environment.sh
#   [ "$status" -eq 0 ]
#   [ "$(get_output_value 'environment')" = "production" ]
# }
#
# # Tests des tags
# @test "le tag v1.0.0 est détecté comme production" {
#   export GITHUB_REF="refs/tags/v1.0.0"
#   export GITHUB_REF_NAME="v1.0.0"
#   run bash ./detect-environment.sh
#   [ "$status" -eq 0 ]
#   [ "$(get_output_value 'environment')" = "production" ]
# }
#
# # Tests de l'i18n
# @test "les messages sont correctement localisés" {
#   export LANGUAGE="en"
#   unset GITHUB_OUTPUT
#   run bash ./detect-environment.sh
#   [ "$status" -eq 1 ]
#   echo "$output" | grep -q "GITHUB_OUTPUT variable not defined"
# }