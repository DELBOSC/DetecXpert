#!/bin/bash
set -euo pipefail

# -----------------------------------
# Variables par défaut et configuration
# -----------------------------------
CONFIG_TYPE="build"
PLATFORMS="android,ios,web,desktop"
OS_VERSIONS=""
API_LEVELS="24,26,29,31,33"
IOS_VERSIONS="14,15,16"
INCLUDE_FLAVORS="true"
FLAVORS="free,premium,professional"
INCLUDE_DIMENSIONS="false"
DIMENSIONS="[]"
EXCLUDE_PATTERNS="[]"
PATH_PREFIX="/build"
DEBUG="false"

# -----------------------------------
# Fonctions d'utilitaires
# -----------------------------------
log_debug() {
  if [[ "$DEBUG" == "true" ]]; then
    echo "::debug::[matrix-config] $1" >&2
  fi
}

log_info() {
  echo "::info::[matrix-config] $1" >&2
}

log_warning() {
  echo "::warning::[matrix-config] $1" >&2
}

log_error() {
  echo "::error::[matrix-config] $1" >&2
  exit 1
}

set_output() {
  local name="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    # Utilisation de la syntaxe actuelle (sera peut-être remplacée à l'avenir par EOF delimiter)
    echo "$name=$value" >> "$GITHUB_OUTPUT"
  else
    # Pour les tests locaux où GITHUB_OUTPUT n'est pas défini
    log_info "Output $name: $value"
  fi
}

# Vérifier que jq est installé
check_jq() {
  if ! command -v jq &> /dev/null; then
    log_error "jq n'est pas installé. Veuillez l'installer avant d'exécuter ce script."
  fi
  
  # Vérifier la version avec une méthode plus robuste
  JQ_VERSION=$(jq --version | cut -d '-' -f2)
  local version_major="${JQ_VERSION%%.*}"
  local version_minor="${JQ_VERSION#*.}"
  version_minor="${version_minor%%.*}" # Extraire uniquement la partie mineure (avant un éventuel point)
  
  if (( version_major < 1 || (version_major == 1 && version_minor < 6) )); then
    log_warning "Version de jq détectée ($JQ_VERSION) est inférieure à 1.6. Certaines fonctionnalités pourraient ne pas fonctionner correctement."
  fi
}

# Valider le JSON
validate_json() {
  local json="$1"
  local name="$2"
  
  if ! echo "$json" | jq . &> /dev/null; then
    log_error "$name n'est pas un JSON valide: $json"
  fi
}

# Valider une valeur booléenne
validate_bool() {
  local value="$1"
  local name="$2"
  
  if [[ "$value" != "true" && "$value" != "false" ]]; then
    log_error "$name doit être 'true' ou 'false', valeur actuelle: $value"
  fi
}

# -----------------------------------
# Parsing des arguments
# -----------------------------------
parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --config-type) CONFIG_TYPE="$2"; shift ;;
      --platforms) PLATFORMS="$2"; shift ;;
      --os-versions) OS_VERSIONS="$2"; shift ;;
      --api-levels) API_LEVELS="$2"; shift ;;
      --ios-versions) IOS_VERSIONS="$2"; shift ;;
      --include-flavors) INCLUDE_FLAVORS="$2"; shift ;;
      --flavors) FLAVORS="$2"; shift ;;
      --include-dimensions) INCLUDE_DIMENSIONS="$2"; shift ;;
      --dimensions) DIMENSIONS="$2"; shift ;;
      --exclude-patterns) EXCLUDE_PATTERNS="$2"; shift ;;
      --path-prefix) PATH_PREFIX="$2"; shift ;;
      --debug) DEBUG="true" ;;
      *) log_error "Argument inconnu: $1" ;;
    esac
    shift
  done
  
  log_debug "Paramètres après parsing:"
  log_debug "CONFIG_TYPE=$CONFIG_TYPE"
  log_debug "PLATFORMS=$PLATFORMS"
  log_debug "OS_VERSIONS=$OS_VERSIONS"
  log_debug "API_LEVELS=$API_LEVELS"
  log_debug "IOS_VERSIONS=$IOS_VERSIONS"
  log_debug "INCLUDE_FLAVORS=$INCLUDE_FLAVORS"
  log_debug "FLAVORS=$FLAVORS"
  log_debug "INCLUDE_DIMENSIONS=$INCLUDE_DIMENSIONS"
  log_debug "DIMENSIONS=$DIMENSIONS"
  log_debug "EXCLUDE_PATTERNS=$EXCLUDE_PATTERNS"
  log_debug "PATH_PREFIX=$PATH_PREFIX"
  log_debug "DEBUG=$DEBUG"
  
  # Validation supplémentaire
  if [[ "$CONFIG_TYPE" != "build" && "$CONFIG_TYPE" != "test" && "$CONFIG_TYPE" != "deploy" ]]; then
    log_error "Type de configuration invalide: $CONFIG_TYPE. Valeurs autorisées: build, test, deploy"
  fi
  
  # Valider les JSON
  validate_json "$DIMENSIONS" "dimensions"
  validate_json "$EXCLUDE_PATTERNS" "exclude-patterns"
  
  # Vérifier les valeurs booléennes
  validate_bool "$INCLUDE_FLAVORS" "include-flavors"
  validate_bool "$INCLUDE_DIMENSIONS" "include-dimensions"
  
  # Vérifier le format du path-prefix
  if [[ ! "$PATH_PREFIX" =~ ^/[^/].*[^/]$ ]]; then
    log_error "path-prefix doit commencer par '/' et ne pas se terminer par '/': $PATH_PREFIX"
  fi
}

# -----------------------------------
# Gestion des plateformes et OS
# -----------------------------------
initialize_platform_os_map() {
  # Initialisation de la structure pour mapper les plateformes et leurs OS
  declare -g -A PLATFORM_OS_MAP
  
  if [[ -z "$OS_VERSIONS" ]]; then
    log_debug "OS_VERSIONS est vide, application des valeurs par défaut par plateforme"
    
    IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"
    for platform in "${PLATFORM_ARRAY[@]}"; do
      case "$platform" in
        android)
          PLATFORM_OS_MAP["$platform"]="$API_LEVELS"
          ;;
        ios)
          PLATFORM_OS_MAP["$platform"]="$IOS_VERSIONS"
          ;;
        web|desktop)
          PLATFORM_OS_MAP["$platform"]="latest"
          ;;
        *)
          log_error "Plateforme non prise en charge: $platform"
          ;;
      esac
    done
    
    # Log pour le debug
    for platform in "${!PLATFORM_OS_MAP[@]}"; do
      log_debug "Plateforme $platform -> ${PLATFORM_OS_MAP[$platform]}"
    done
  else
    log_debug "OS_VERSIONS est spécifié, analyse des versions par plateforme"
    
    # Format OS_VERSIONS attendu: "android:24,26,29,31,33;ios:14,15,16;web:latest;desktop:latest"
    IFS=';' read -ra PLATFORM_OS_PAIRS <<< "$OS_VERSIONS"
    for pair in "${PLATFORM_OS_PAIRS[@]}"; do
      # Séparer la plateforme et les versions
      IFS=':' read -ra PARTS <<< "$pair"
      if [[ ${#PARTS[@]} -eq 2 ]]; then
        platform="${PARTS[0]}"
        versions="${PARTS[1]}"
        PLATFORM_OS_MAP["$platform"]="$versions"
        log_debug "Parsé depuis OS_VERSIONS: $platform -> $versions"
      else
        log_error "Format invalide dans OS_VERSIONS: $pair. Format attendu: plateforme:versions"
      fi
    done
    
    # Vérifier que toutes les plateformes ont des versions d'OS définies
    IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"
    for platform in "${PLATFORM_ARRAY[@]}"; do
      if [[ -z "${PLATFORM_OS_MAP[$platform]:-}" ]]; then
        log_warning "Aucune version d'OS définie pour la plateforme $platform dans OS_VERSIONS. Utilisation de la valeur par défaut."
        
        case "$platform" in
          android)
            PLATFORM_OS_MAP["$platform"]="$API_LEVELS"
            ;;
          ios)
            PLATFORM_OS_MAP["$platform"]="$IOS_VERSIONS"
            ;;
          web|desktop)
            PLATFORM_OS_MAP["$platform"]="latest"
            ;;
          *)
            log_error "Plateforme non prise en charge: $platform"
            ;;
        esac
      fi
    done
  fi
}

# -----------------------------------
# Génération de matrice
# -----------------------------------
generate_matrix() {
  local include_items=()
  local total_combinations=0
  
  log_debug "Génération de la matrice"
  
  # Initialiser la matrice avec les plateformes
  IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"
  
  # Pour chaque plateforme, générer les combinaisons avec OS
  for platform in "${PLATFORM_ARRAY[@]}"; do
    os_versions="${PLATFORM_OS_MAP[$platform]}"
    log_debug "Traitement plateforme $platform avec versions OS: $os_versions"
    
    IFS=',' read -ra OS_ARRAY <<< "$os_versions"
    for os_version in "${OS_ARRAY[@]}"; do
      # Base item pour cette plateforme et version OS
      local base_item="{\"platform\":\"$platform\",\"os-version\":\"$os_version\"}"
      
      # Ajouter les flavors si demandé
      if [[ "$INCLUDE_FLAVORS" == "true" ]]; then
        IFS=',' read -ra FLAVOR_ARRAY <<< "$FLAVORS"
        for flavor in "${FLAVOR_ARRAY[@]}"; do
          local item_with_flavor=$(echo "$base_item" | jq --arg flavor "$flavor" '. += {"flavor": $flavor}')
          include_items+=("$item_with_flavor")
        done
      else
        include_items+=("$base_item")
      fi
    done
  done
  
  # Convertir les items en JSON array
  local include_array=$(printf '%s\n' "${include_items[@]}" | jq -s '.')
  log_debug "Items de base générés: $(echo "$include_array" | jq length) combinaisons"
  
  # Ajouter les dimensions supplémentaires si demandé
  if [[ "$INCLUDE_DIMENSIONS" == "true" && "$DIMENSIONS" != "[]" ]]; then
    log_debug "Application des dimensions supplémentaires: $DIMENSIONS"
    
    # Pour chaque dimension, expandre la matrice
    # On parse le JSON pour obtenir les dimensions
    local dimensions_json="$DIMENSIONS"
    local dimensions_count=$(echo "$dimensions_json" | jq length)
    log_debug "Nombre de dimensions à appliquer: $dimensions_count"
    
    # Pour chaque dimension
    for ((i=0; i<$dimensions_count; i++)); do
      local dimension=$(echo "$dimensions_json" | jq -r ".[$i]")
      local dimension_name=$(echo "$dimension" | jq -r ".name")
      local dimension_values=$(echo "$dimension" | jq -r ".values | join(\",\")")
      
      log_debug "Application dimension: $dimension_name avec valeurs: $dimension_values"
      
      # Créer un nouvel array pour les items expandés
      local expanded_items=()
      
      # Pour chaque item existant
      local items_count=$(echo "$include_array" | jq length)
      for ((j=0; j<$items_count; j++)); do
        local item=$(echo "$include_array" | jq -r ".[$j]")
        
        # Pour chaque valeur de la dimension
        IFS=',' read -ra DIM_VALUES <<< "$dimension_values"
        for dim_value in "${DIM_VALUES[@]}"; do
          # Ajouter la dimension à l'item
          local expanded_item=$(echo "$item" | jq --arg name "$dimension_name" --arg value "$dim_value" '. += {($name): $value}')
          expanded_items+=("$expanded_item")
        done
      done
      
      # Mettre à jour include_array avec les items expandés
      include_array=$(printf '%s\n' "${expanded_items[@]}" | jq -s '.')
      log_debug "Après dimension $dimension_name: $(echo "$include_array" | jq length) combinaisons"
    done
  fi
  
  # Ajouter le préfixe de chemin à chaque élément
  include_array=$(echo "$include_array" | jq --arg prefix "$PATH_PREFIX" 'map(. + {"path-prefix": $prefix})')
  
  # Filtrer selon les patterns d'exclusion
  if [[ "$EXCLUDE_PATTERNS" != "[]" ]]; then
    log_debug "Application des patterns d'exclusion: $EXCLUDE_PATTERNS"
    
    # Utiliser jq pour faire le filtrage d'exclusion de manière plus efficace
    include_array=$(echo "$include_array" | jq --argjson excl "$EXCLUDE_PATTERNS" '
      [
        .[] | 
        select(
          ($excl | map(
            . as $pattern |
            . | keys | all(
              . as $key |
              if $pattern[$key] != null and .[$key] == $pattern[$key] then
                false
              else
                true
              end
            )
          )) | all
        )
      ]
    ')
    
    log_debug "Après exclusion: $(echo "$include_array" | jq length) combinaisons"
  fi
  
  # Calculer le nombre total de combinaisons
  total_combinations=$(echo "$include_array" | jq 'length')
  log_debug "Nombre total de combinaisons finales: $total_combinations"
  
  # Créer la matrice finale pour GitHub Actions
  if [[ $total_combinations -eq 0 ]]; then
    log_warning "Aucune combinaison générée. Vérifiez vos entrées et patterns d'exclusion."
    # Fournir une matrice par défaut simple pour éviter les erreurs
    set_output "matrix" "{\"include\": [{\"platform\": \"${PLATFORM_ARRAY[0]}\", \"os-version\": \"latest\", \"path-prefix\": \"$PATH_PREFIX\"}]}"
    set_output "matrix-include" "[]"
    set_output "matrix-exclude" "[]"
    set_output "total-combinations" "1"
  else
    # Définir les outputs
    log_debug "Génération des outputs pour GitHub Actions"
    
    # Format pour la sortie GitHub Actions
    set_output "matrix" "{\"include\": $include_array}"
    
    # Pour les include/exclude supplémentaires si nécessaire
    set_output "matrix-include" "[]"
    set_output "matrix-exclude" "[]"
    
    set_output "total-combinations" "$total_combinations"
  fi
}

# -----------------------------------
# Point d'entrée principal
# -----------------------------------
main() {
  check_jq
  parse_args "$@"
  initialize_platform_os_map
  generate_matrix
  log_info "Génération de la matrice terminée avec succès"
}

# Exécuter le script
main "$@"