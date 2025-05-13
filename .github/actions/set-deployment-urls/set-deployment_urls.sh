#!/bin/bash
#
# Script de génération d'URLs de déploiement pour DetectXpert
# 
# Paramètres d'environnement:
# - INPUT_ENVIRONMENT       [requis] Environnement (dev, staging, prod)
# - INPUT_VERSION           [requis] Version du déploiement (format SemVer recommandé)
# - INPUT_BASE_DOMAIN       [optionnel] Domaine de base (défaut: detectxpert.com)
# - INPUT_INCLUDE_VERSION_IN_URL [optionnel] Inclure version dans URL (true/false, défaut: false)
# - INPUT_CUSTOM_PREFIX     [optionnel] Préfixe personnalisé remplaçant environment
# - INPUT_USE_HTTPS         [optionnel] Utiliser HTTPS (true/false, défaut: true)
# - INPUT_PATH_PREFIX       [optionnel] Préfixe de chemin (/app, /api, etc.)
# - INPUT_DEBUG             [optionnel] Activer le mode debug (true/false, défaut: false)
# - INPUT_OUTPUT_JSON       [optionnel] Générer une sortie JSON (true/false, défaut: false)
# - INPUT_JSON_OUTPUT_FILE  [optionnel] Chemin du fichier de sortie JSON
# - INPUT_LOCALE            [optionnel] Langue des messages (fr, en, défaut: fr)
#
# Outputs GitHub Actions:
# - main-url                URL principale de l'application
# - api-url                 URL de l'API
# - dashboard-url           URL du tableau de bord
# - docs-url                URL de la documentation
# - deployment-id           ID unique du déploiement
#
# Format de sortie JSON si OUTPUT_JSON=true:
# {
#   "main_url": "https://environment.domain.com/path/",
#   "api_url": "https://api.environment.domain.com/path/",
#   "dashboard_url": "https://dashboard.environment.domain.com/path/",
#   "docs_url": "https://docs.environment.domain.com/path/",
#   "deployment_id": "env-1.0.0-20250512120000",
#   "environment": "environment",
#   "version": "1.0.0",
#   "include_version_in_url": false,
#   "custom_prefix": "",
#   "use_https": true,
#   "base_domain": "domain.com",
#   "timestamp": "20250512120000"
# }
#
# Exemples d'utilisation:
# 
# 1. Utilisation basique:
#    INPUT_ENVIRONMENT=staging \
#    INPUT_VERSION=1.2.3 \
#    INPUT_BASE_DOMAIN=detectxpert.com \
#    ./set-deployment-urls.sh
#
# 2. Avec JSON et fichier de sortie:
#    INPUT_ENVIRONMENT=staging \
#    INPUT_VERSION=1.2.3 \
#    INPUT_OUTPUT_JSON=true \
#    INPUT_JSON_OUTPUT_FILE=/tmp/urls.json \
#    ./set-deployment-urls.sh

set -euo pipefail

# Gestion centralisée des fichiers temporaires
TMP_FILES=()
cleanup() {
  for tmp_file in "${TMP_FILES[@]}"; do
    [[ -f "$tmp_file" ]] && rm -f "$tmp_file"
  done
}
trap cleanup EXIT

# Créer un fichier temporaire et l'ajouter à la liste
create_tmp_file() {
  local tmp_file
  tmp_file=$(mktemp)
  TMP_FILES+=("$tmp_file")
  echo "$tmp_file"
}

# Constantes
VALID_ENVIRONMENTS="dev|staging|prod"
VALID_DOMAIN_REGEX='^[a-z0-9.-]+\.[a-z]{2,}$'
VALID_PREFIX_REGEX='^[a-z0-9-]+$'
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
DEBUG="${INPUT_DEBUG:-false}"
OUTPUT_JSON="${INPUT_OUTPUT_JSON:-false}"
LOCALE="${INPUT_LOCALE:-fr}"

# Messages d'erreur centralisés - pour faciliter l'internationalisation future
if [[ "${LOCALE}" == "fr" ]]; then
  ERR_VERSION_EMPTY="::error::La variable VERSION est vide"
  ERR_ENV_INVALID="::error::Environnement invalide: '%s' (valeurs acceptées: %s)"
  ERR_PREFIX_INVALID="::error::Le préfixe personnalisé '%s' doit uniquement contenir des lettres minuscules, chiffres et tirets (regex: %s)"
  ERR_DOMAIN_INVALID="::error::Domaine de base invalide: '%s' (format attendu: example.com, sous-domaine.example.co.uk, etc.)"
  ERR_JSON_INVALID="::error::Échec de génération JSON avec jq: %s"
  WARN_VERSION_FORMAT="::warning::Format de version '%s' non conforme à SemVer (format attendu: x.y.z[-pré][+build])"
  WARN_JQ_MISSING="::warning::jq n'est pas disponible, construction JSON manuelle (échappement limité)"
  LOG_JSON_SAVED="Sortie JSON sauvegardée dans: %s"
  LOG_SKIP_GITHUB="Variable GITHUB_OUTPUT non définie, skip génération des outputs GitHub Actions"
else
  # English messages
  ERR_VERSION_EMPTY="::error::VERSION variable is empty"
  ERR_ENV_INVALID="::error::Invalid environment: '%s' (accepted values: %s)"
  ERR_PREFIX_INVALID="::error::Custom prefix '%s' must only contain lowercase letters, numbers and hyphens (regex: %s)"
  ERR_DOMAIN_INVALID="::error::Invalid base domain: '%s' (expected format: example.com, subdomain.example.co.uk, etc.)"
  ERR_JSON_INVALID="::error::JSON generation with jq failed: %s"
  WARN_VERSION_FORMAT="::warning::Version format '%s' is not compliant with SemVer (expected format: x.y.z[-pre][+build])"
  WARN_JQ_MISSING="::warning::jq is not available, using manual JSON construction (limited escaping)"
  LOG_JSON_SAVED="JSON output saved to: %s"
  LOG_SKIP_GITHUB="GITHUB_OUTPUT variable not defined, skipping GitHub Actions outputs generation"
fi

# Afficher une erreur formatée
error() {
  local error_msg="$1"
  shift
  printf "${error_msg}\n" "$@" >&2
}

# Logging conditionnel basé sur DEBUG
log() {
  if [[ "${DEBUG}" == "true" ]]; then
    echo "$@"
  fi
}

# Normaliser les valeurs booléennes (case-insensitive)
normalize_bool() {
  local val="${1,,}" # lowercase
  val="${val:-false}"
  
  # Accepter 1/0 en plus de true/false
  if [[ "${val}" == "1" ]]; then
    echo "true"
  elif [[ "${val}" == "0" ]]; then
    echo "false"
  else
    echo "${val}"
  fi
}

# Retourne la date/heure actuelle au format YYYYMMDDhhmmss
# Peut être surchargée dans les tests
now() {
  date +%Y%m%d%H%M%S
}

# Fonction de validation des entrées
validate_inputs() {
  local version="$1"
  local environment="$2"
  local custom_prefix="$3"
  local base_domain="$4"

  # Vérification que VERSION n'est pas vide
  if [[ -z "$version" ]]; then
    error "${ERR_VERSION_EMPTY}"
    return 1
  fi

  # Validation de l'environnement
  if ! [[ "$environment" =~ ^(${VALID_ENVIRONMENTS})$ ]]; then
    # Formatter le message avec les valeurs attendues explicites
    local expected_values
    expected_values=$(echo "${VALID_ENVIRONMENTS}" | sed 's/|/, /g')
    error "${ERR_ENV_INVALID}" "$environment" "${expected_values}"
    return 1
  fi

  # Validation du préfixe personnalisé
  if [[ -n "$custom_prefix" && ! "$custom_prefix" =~ ${VALID_PREFIX_REGEX} ]]; then
    error "${ERR_PREFIX_INVALID}" "$custom_prefix" "${VALID_PREFIX_REGEX}"
    return 1
  fi

  # Validation du nom de domaine
  if [[ ! "$base_domain" =~ ${VALID_DOMAIN_REGEX} ]]; then
    error "${ERR_DOMAIN_INVALID}" "$base_domain"
    return 1
  fi

  # Validation du format SemVer complet
  if [[ ! "$version" =~ ${SEMVER_REGEX} ]]; then
    error "${WARN_VERSION_FORMAT}" "$version"
    # Continuer malgré l'avertissement
  fi

  return 0
}

# Normalisation du PATH_PREFIX
normalize_path_prefix() {
  local path_prefix="$1"
  
  if [[ -z "$path_prefix" ]]; then
    echo ""
    return
  fi
  
  # S'assurer qu'il commence par /
  if ! [[ "$path_prefix" =~ ^/ ]]; then
    path_prefix="/$path_prefix"
  fi
  
  # S'assurer qu'il ne se termine pas par /
  path_prefix="${path_prefix%/}"
  
  # Normaliser les doubles slashes
  while [[ "$path_prefix" == *"//"* ]]; do
    path_prefix="${path_prefix//\/\//\/}"
  done
  
  echo "$path_prefix"
}

# Fonction de construction d'URL
build_url() {
  local subdomain="$1"
  local prefix="$2"
  local base_domain="$3"
  local proto="$4"
  local path_prefix="$5"
  local include_version="$6"
  local version="$7"
  local host
  
  # Construire le hostname
  if [[ -n "$subdomain" ]]; then
    host="${subdomain}.${prefix}.${base_domain}"
  else
    host="${prefix}.${base_domain}"
  fi
  
  # Construire le chemin complet
  local path="$path_prefix"
  
  # Ajouter la version dans le chemin si nécessaire
  if [[ "$include_version" == "true" ]]; then
    if [[ -n "$path" ]]; then
      path="${path}/v${version}"
    else
      path="/v${version}"
    fi
  fi
  
  # Assurer que le chemin se termine par un /
  if [[ -n "$path" ]]; then
    path="${path}/"
  else
    path="/"
  fi
  
  # Normaliser les doubles slashes potentiels - simple substitution globale
  path="${path//\/\//\/}"
  
  echo "${proto}://${host}${path}"
}

# Génère une sortie JSON avec les données d'URL
generate_json_output() {
  local main_url="$1"
  local api_url="$2"
  local dashboard_url="$3"
  local docs_url="$4"
  local deployment_id="$5"
  local environment="$6"
  local version="$7"
  local include_version_in_url="$8"
  local custom_prefix="$9"
  local use_https="${10}"
  local base_domain="${11}"
  local timestamp="${12}"
  
  # Vérifier si jq est disponible
  if command -v jq >/dev/null 2>&1; then
    # Créer un fichier temporaire pour capturer les erreurs
    local jq_error_file
    jq_error_file=$(create_tmp_file)
    
    # Utiliser jq pour un JSON garantie valide
    local json_output
    json_output=$(jq -n \
      --arg main_url "${main_url}" \
      --arg api_url "${api_url}" \
      --arg dashboard_url "${dashboard_url}" \
      --arg docs_url "${docs_url}" \
      --arg deployment_id "${deployment_id}" \
      --arg environment "${environment}" \
      --arg version "${version}" \
      --argjson include_version_in_url ${include_version_in_url} \
      --arg custom_prefix "${custom_prefix}" \
      --argjson use_https ${use_https} \
      --arg base_domain "${base_domain}" \
      --arg timestamp "${timestamp}" \
      '{
        main_url: $main_url,
        api_url: $api_url,
        dashboard_url: $dashboard_url,
        docs_url: $docs_url,
        deployment_id: $deployment_id,
        environment: $environment,
        version: $version,
        include_version_in_url: $include_version_in_url,
        custom_prefix: $custom_prefix,
        use_https: $use_https,
        base_domain: $base_domain,
        timestamp: $timestamp
      }' 2> "${jq_error_file}" || true)
    
    # Vérifier si jq a réussi
    if [[ -s "${jq_error_file}" ]]; then
      jq_error=$(cat "${jq_error_file}")
      error "${ERR_JSON_INVALID}" "${jq_error}"
      # Retourner un statut indiquant que jq a échoué, mais continuer l'exécution
      return 1
    else
      echo "${json_output}"
      return 0
    fi
  else
    # jq n'est pas disponible
    error "${WARN_JQ_MISSING}"
    return 1
  fi
}

# Génère une sortie JSON de fallback (sans jq)
generate_fallback_json() {
  local main_url="$1"
  local api_url="$2"
  local dashboard_url="$3"
  local docs_url="$4"
  local deployment_id="$5"
  local environment="$6"
  local version="$7"
  local include_version_in_url="$8"
  local custom_prefix="$9"
  local use_https="${10}"
  local base_domain="${11}"
  local timestamp="${12}"
  
  # Fallback avec échappement manuel des guillemets
  cat <<EOF
{
  "main_url": "${main_url//\"/\\\"}",
  "api_url": "${api_url//\"/\\\"}",
  "dashboard_url": "${dashboard_url//\"/\\\"}",
  "docs_url": "${docs_url//\"/\\\"}",
  "deployment_id": "${deployment_id//\"/\\\"}",
  "environment": "${environment//\"/\\\"}",
  "version": "${version//\"/\\\"}",
  "include_version_in_url": ${include_version_in_url},
  "custom_prefix": "${custom_prefix//\"/\\\"}",
  "use_https": ${use_https},
  "base_domain": "${base_domain//\"/\\\"}",
  "timestamp": "${timestamp//\"/\\\"}"
}
EOF
}

# Normalisation des entrées
ENVIRONMENT="${INPUT_ENVIRONMENT:-}"
VERSION="${INPUT_VERSION:-}"
BASE_DOMAIN="${INPUT_BASE_DOMAIN:-detectxpert.com}"
INCLUDE_VERSION_IN_URL="$(normalize_bool "${INPUT_INCLUDE_VERSION_IN_URL:-false}")"
CUSTOM_PREFIX="${INPUT_CUSTOM_PREFIX:-}"
USE_HTTPS="$(normalize_bool "${INPUT_USE_HTTPS:-true}")"
PATH_PREFIX=$(normalize_path_prefix "${INPUT_PATH_PREFIX:-}")
TIMESTAMP="$(now)"

# Validation des entrées
validate_inputs "${VERSION}" "${ENVIRONMENT}" "${CUSTOM_PREFIX}" "${BASE_DOMAIN}" || exit 1

# Déterminer le préfixe pour les URLs
PREFIX="${CUSTOM_PREFIX:-$ENVIRONMENT}"

# Déterminer le protocole
PROTO="http"
if [[ "${USE_HTTPS}" == "true" ]]; then
  PROTO="https"
fi

# Générer les URLs
MAIN_URL=$(build_url "" "${PREFIX}" "${BASE_DOMAIN}" "${PROTO}" "${PATH_PREFIX}" "${INCLUDE_VERSION_IN_URL}" "${VERSION}")
API_URL=$(build_url "api" "${PREFIX}" "${BASE_DOMAIN}" "${PROTO}" "${PATH_PREFIX}" "${INCLUDE_VERSION_IN_URL}" "${VERSION}")
DASHBOARD_URL=$(build_url "dashboard" "${PREFIX}" "${BASE_DOMAIN}" "${PROTO}" "${PATH_PREFIX}" "${INCLUDE_VERSION_IN_URL}" "${VERSION}")
DOCS_URL=$(build_url "docs" "${PREFIX}" "${BASE_DOMAIN}" "${PROTO}" "${PATH_PREFIX}" "${INCLUDE_VERSION_IN_URL}" "${VERSION}")

# Générer un ID de déploiement unique
DEPLOYMENT_ID="${PREFIX}-${VERSION}-${TIMESTAMP}"

# Afficher les URLs pour le débogage
log "Main URL: ${MAIN_URL}"
log "API URL: ${API_URL}"
log "Dashboard URL: ${DASHBOARD_URL}"
log "Docs URL: ${DOCS_URL}"
log "Deployment ID: ${DEPLOYMENT_ID}"

# Créer la sortie au format JSON si demandé
if [[ "${OUTPUT_JSON}" == "true" ]]; then
  # Essayer de générer un JSON avec jq
  JSON_OUTPUT=$(generate_json_output \
    "${MAIN_URL}" \
    "${API_URL}" \
    "${DASHBOARD_URL}" \
    "${DOCS_URL}" \
    "${DEPLOYMENT_ID}" \
    "${ENVIRONMENT}" \
    "${VERSION}" \
    "${INCLUDE_VERSION_IN_URL}" \
    "${CUSTOM_PREFIX}" \
    "${USE_HTTPS}" \
    "${BASE_DOMAIN}" \
    "${TIMESTAMP}")
  
  # Si jq a échoué ou n'est pas disponible, utiliser le fallback
  if [[ $? -ne 0 ]]; then
    JSON_OUTPUT=$(generate_fallback_json \
      "${MAIN_URL}" \
      "${API_URL}" \
      "${DASHBOARD_URL}" \
      "${DOCS_URL}" \
      "${DEPLOYMENT_ID}" \
      "${ENVIRONMENT}" \
      "${VERSION}" \
      "${INCLUDE_VERSION_IN_URL}" \
      "${CUSTOM_PREFIX}" \
      "${USE_HTTPS}" \
      "${BASE_DOMAIN}" \
      "${TIMESTAMP}")
  fi
  
  # Afficher le JSON
  echo "${JSON_OUTPUT}"
  
  # Sauvegarder dans un fichier si demandé
  if [[ -n "${INPUT_JSON_OUTPUT_FILE:-}" ]]; then
    echo "${JSON_OUTPUT}" > "${INPUT_JSON_OUTPUT_FILE}"
    log "$(printf "${LOG_JSON_SAVED}" "${INPUT_JSON_OUTPUT_FILE}")"
  fi
fi

# Définir les outputs pour GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "main-url=${MAIN_URL}" >> "${GITHUB_OUTPUT}"
  echo "api-url=${API_URL}" >> "${GITHUB_OUTPUT}"
  echo "dashboard-url=${DASHBOARD_URL}" >> "${GITHUB_OUTPUT}"
  echo "docs-url=${DOCS_URL}" >> "${GITHUB_OUTPUT}"
  echo "deployment-id=${DEPLOYMENT_ID}" >> "${GITHUB_OUTPUT}"
else
  log "${LOG_SKIP_GITHUB}"
fi

# Sortie réussie pour les tests
exit 0