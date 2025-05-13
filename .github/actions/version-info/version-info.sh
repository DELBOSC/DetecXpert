#!/usr/bin/env bash

# Script: version-info.sh
# Description: Extrait et manipule les informations de version pour les projets
# Auteur: Amélioré par Claude pour DetectXpert

# Gestion stricte des erreurs
set -euo pipefail

# =====================================================================
# CONSTANTES
# =====================================================================

# Codes de sortie
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_VERSION=2
readonly EXIT_JSON_PARSE_ERROR=3
readonly EXIT_INVALID_BUMP=4
readonly EXIT_DATE_ERROR=5
readonly EXIT_DEPENDENCY_MISSING=6
readonly EXIT_INVALID_PARAM=7

# Chemins par défaut
readonly DEFAULT_GRADLE_PATH="./gradle.properties"
readonly DEFAULT_VERSION_KT_PATH="./build-system/gradle/core/Versions.kt"
readonly DEFAULT_VERSION_PREFIX="v"

# Valeurs acceptées
readonly VALID_SNAPSHOT_MODES="true false auto"
readonly VALID_BUMP_TYPES="major minor patch"

# Messages localisés
readonly MSG_HELP_TITLE="Utilisation: version-info.sh"
readonly MSG_HELP_ENV="Environnement:"
readonly MSG_MODE_DRYRUN="Mode dry-run activé, les valeurs suivantes sont factices"
readonly MSG_ERROR_MISSING_FILES="Ni gradle.properties ni Versions.kt n'existent aux emplacements spécifiés"
readonly MSG_ERROR_NO_VERSION="Impossible d'extraire la version des fichiers spécifiés"
readonly MSG_ERROR_INVALID_VERSION="Version extraite invalide"
readonly MSG_ERROR_INVALID_SNAPSHOT="Mode snapshot non valide. Valeurs acceptées : true, false, auto"
readonly MSG_ERROR_INVALID_BUMP_TYPE="Type de bump non valide. Valeurs acceptées : major, minor, patch"
readonly MSG_USING_CUSTOM="Utilisation de la version personnalisée"
readonly MSG_EXTRACTED_GRADLE="Version extraite de gradle.properties"
readonly MSG_EXTRACTED_KOTLIN="Version extraite de Versions.kt"
readonly MSG_VERSION_AFTER_BUMP="Version après bump"
readonly MSG_WARNING_SNAPSHOT="Mode snapshot non reconnu, utilisation de 'auto'"
readonly MSG_USING_JSON="Utilisation de la configuration JSON fournie"
readonly MSG_WARNING_NO_JQ="jq n'est pas disponible, utilisation d'un parsing JSON simplifié (limité aux clés simples, sans tableaux ni objets imbriqués)"
readonly MSG_ERROR_JQ_REQUIRED="L'outil jq est requis pour traiter des configurations JSON complexes. Installez-le avec 'apt-get install jq' ou 'brew install jq'."
readonly MSG_ERROR_GIT_MISSING="Git est requis mais n'est pas installé"
readonly MSG_ERROR_INVALID_BUMP="Type de bump non reconnu"
readonly MSG_FINAL_VERSION="Version extraite"
readonly MSG_FINAL_CODE="Version numérique"
readonly MSG_FINAL_SNAPSHOT="Est un snapshot"
readonly MSG_FINAL_RELEASE="Est une release"

# Patterns regex (utilisant les classes POSIX pour une meilleure portabilité)
readonly REGEX_VERSION="^[0-9]+(\.[0-9]+){0,2}(-[A-Za-z0-9]+)?$"
readonly REGEX_GRADLE_VERSION="^(version|VERSION_NAME|appVersion)[[:space:]]*=[[:space:]]*[\"']?([^\"']+)[\"']?"
readonly REGEX_KOTLIN_VERSION="(val APP_VERSION|const val VERSION_NAME)[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"']"

# Branches de production (peuvent être overridées par PRODUCTION_BRANCHES)
readonly DEFAULT_PRODUCTION_BRANCHES="main master release.* hotfix.*"

# =====================================================================
# FONCTIONS D'AIDE
# =====================================================================

# Affiche l'aide du script
usage() {
  cat <<EOF
$MSG_HELP_TITLE
  $MSG_HELP_ENV
    GRADLE_PROPERTIES_PATH: Chemin vers gradle.properties (défaut: $DEFAULT_GRADLE_PATH)
    VERSION_FILE_PATH: Chemin vers Versions.kt (défaut: $DEFAULT_VERSION_KT_PATH)
    CUSTOM_VERSION: Version personnalisée (optionnel)
    SNAPSHOT_MODE: Mode snapshot 'true', 'false', ou 'auto' (défaut: auto)
    VERSION_PREFIX: Préfixe de version (défaut: $DEFAULT_VERSION_PREFIX)
    DRY_RUN: Mode simulation 'true' ou 'false' (défaut: false)
    BUMP: Incrémenter 'major', 'minor', ou 'patch' (optionnel)
    CONFIG_JSON: Configuration JSON (optionnel)
    PRODUCTION_BRANCHES: Branches considérées en production, séparées par espaces (défaut: "$DEFAULT_PRODUCTION_BRANCHES")

  Codes de sortie:
    $EXIT_SUCCESS - Succès
    $EXIT_GENERAL_ERROR - Erreur générale (fichier introuvable)
    $EXIT_INVALID_VERSION - Format de version invalide
    $EXIT_JSON_PARSE_ERROR - Erreur de parsing JSON
    $EXIT_INVALID_BUMP - Type de bump invalide
    $EXIT_DATE_ERROR - Erreur dans le traitement de la date
    $EXIT_DEPENDENCY_MISSING - Dépendance requise manquante
    $EXIT_INVALID_PARAM - Paramètre d'entrée invalide

  Convention de nommage:
    - Les variables d'entrée sont en MAJUSCULES (CONFIG_JSON, GRADLE_PROPERTIES_PATH)
    - Les variables internes sont en camelCase ou snake_case (config_json, gradle_properties_path)

  Exemples d'utilisation:
    ./version-info.sh                            # Utilisation simple avec valeurs par défaut
    
    # Spécifier une version personnalisée et mode de snapshot
    CUSTOM_VERSION=1.2.3 SNAPSHOT_MODE=false ./version-info.sh
    
    # Incrémenter une version et définir un préfixe personnalisé
    BUMP=minor VERSION_PREFIX=version- ./version-info.sh
    
    # Définir les branches de production à considérer
    PRODUCTION_BRANCHES="main release/*" ./version-info.sh
    
    # Utiliser une configuration JSON
    CONFIG_JSON='{"customVersion":"2.0.0","bump":"major"}' ./version-info.sh
EOF
}

# Vérifie si une commande est disponible
check_command() {
  command -v "$1" >/dev/null 2>&1
}

# Vérifie les dépendances critiques
validate_dependencies() {
  # Git est toujours requis
  if ! check_command "git"; then
    echo "::error::$MSG_ERROR_GIT_MISSING" >&2
    exit $EXIT_DEPENDENCY_MISSING
  fi
  
  # Si une configuration JSON complexe est détectée mais jq est absent
  if [[ -n "${CONFIG_JSON:-}" ]] && 
     [[ "$CONFIG_JSON" == *"{"*"{"* || "$CONFIG_JSON" == *"["*"]"* || "$CONFIG_JSON" == *"}"*"}"* ]] && 
     ! check_command "jq"; then
    echo "::error::$MSG_ERROR_JQ_REQUIRED" >&2
    exit $EXIT_DEPENDENCY_MISSING
  fi
}

# Vérifie si jq est disponible
has_jq() {
  check_command "jq" && echo "true" || echo "false"
}

# Valide les paramètres d'entrée
validate_input_params() {
  local snapshot_mode="${1:-auto}"
  local bump="${2:-}"
  
  # Validation du mode snapshot
  if [[ -n "$snapshot_mode" && "$snapshot_mode" != "auto" ]]; then
    local valid_snapshot=false
    for mode in $VALID_SNAPSHOT_MODES; do
      if [[ "$snapshot_mode" == "$mode" ]]; then
        valid_snapshot=true
        break
      fi
    done
    
    if [[ "$valid_snapshot" != "true" ]]; then
      echo "::error::$MSG_ERROR_INVALID_SNAPSHOT" >&2
      exit $EXIT_INVALID_PARAM
    fi
  fi
  
  # Validation du type de bump si spécifié
  if [[ -n "$bump" ]]; then
    local valid_bump=false
    for type in $VALID_BUMP_TYPES; do
      if [[ "$bump" == "$type" ]]; then
        valid_bump=true
        break
      fi
    done
    
    if [[ "$valid_bump" != "true" ]]; then
      echo "::error::$MSG_ERROR_INVALID_BUMP_TYPE" >&2
      exit $EXIT_INVALID_PARAM
    fi
  fi
}

# Écrit une valeur dans le fichier de sortie GitHub avec protection contre les caractères spéciaux
write_output() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

# =====================================================================
# FONCTIONS DE DATE ET GIT
# =====================================================================

# Obtient la date de build au format ISO 8601
get_build_date() {
  local date_command date_format date_str
  date_format="%Y-%m-%dT%H:%M:%SZ"
  
  # Essaie d'abord la commande 'date'
  if date -u +"$date_format" >/dev/null 2>&1; then
    date_command="date -u"
  # Fallback sur 'gdate' (GNU date sur macOS via coreutils)
  elif check_command "gdate" && gdate -u +"$date_format" >/dev/null 2>&1; then
    date_command="gdate -u"
  # Dernier recours: date sans -u (moins précis)
  else
    date_command="date"
  fi
  
  date_str=$($date_command +"$date_format" 2>/dev/null || echo "")
  
  if [[ -z "$date_str" ]]; then
    echo "::error::Impossible de générer la date ISO" >&2
    exit $EXIT_DATE_ERROR
  fi
  
  echo "$date_str"
}

# Obtient le hash du commit git actuel
get_git_commit() {
  git rev-parse HEAD 2>/dev/null || echo "unknown"
}

# Obtient la branche git actuelle
get_current_branch() {
  # Essaie d'abord les variables d'environnement GitHub Actions
  if [[ -n "${GITHUB_HEAD_REF:-}" ]]; then
    echo "$GITHUB_HEAD_REF"
  elif [[ -n "${GITHUB_REF:-}" && "$GITHUB_REF" == refs/heads/* ]]; then
    echo "${GITHUB_REF#refs/heads/}"
  # Fallback sur git
  else
    git symbolic-ref --short HEAD 2>/dev/null || echo ""
  fi
}

# Vérifie si la branche actuelle est une branche de production
is_production_branch() {
  local branch="$1"
  local prod_branches="${PRODUCTION_BRANCHES:-$DEFAULT_PRODUCTION_BRANCHES}"
  
  [[ -z "$branch" ]] && return 1
  
  for pattern in $prod_branches; do
    if [[ "$branch" == $pattern ]]; then
      return 0
    fi
  done
  
  return 1
}

# =====================================================================
# FONCTIONS D'EXTRACTION DE VERSION
# =====================================================================

# Extrait la version de gradle.properties
extract_from_gradle_properties() {
  local file="$1"
  local version=""
  
  if [[ -f "$file" ]]; then
    # Utilise grep avec regex pour trouver les variantes de déclaration de version
    version=$(grep -E "$REGEX_GRADLE_VERSION" "$file" | head -1 | sed -E "s/$REGEX_GRADLE_VERSION/\2/" || echo "")
  fi
  
  echo "$version"
}

# Extrait la version de Versions.kt
extract_from_versions_kt() {
  local file="$1"
  local version=""
  
  if [[ -f "$file" ]]; then
    # Utilise grep avec regex pour trouver les variantes de déclaration de version
    version=$(grep -E "$REGEX_KOTLIN_VERSION" "$file" | head -1 | sed -E "s/$REGEX_KOTLIN_VERSION/\2/" || echo "")
  fi
  
  echo "$version"
}

# Valide le format de la version
validate_version_format() {
  local version="$1"
  
  if [[ ! "$version" =~ $REGEX_VERSION ]]; then
    echo "::error::$MSG_ERROR_INVALID_VERSION: $version" >&2
    return $EXIT_INVALID_VERSION
  fi
  
  return $EXIT_SUCCESS
}

# =====================================================================
# FONCTIONS DE MANIPULATION DE VERSION
# =====================================================================

# Détermine automatiquement si la version devrait être un snapshot
is_snapshot_auto() {
  local version="$1"
  
  # Déjà un snapshot explicite
  if [[ "$version" == *"-SNAPSHOT"* ]]; then
    echo "true"
    return
  fi
  
  # Si ce n'est pas une branche de production
  local branch
  branch=$(get_current_branch)
  if ! is_production_branch "$branch"; then
    echo "true"
    return
  fi
  
  # Si le commit n'est pas taggé
  if ! git describe --exact-match --tags HEAD >/dev/null 2>&1; then
    echo "true"
    return
  fi
  
  # Par défaut: pas un snapshot
  echo "false"
}

# Incrémente la version selon le type de bump
bump_version() {
  local version="$1"
  local bump_type="$2"
  
  # Nettoie le suffixe SNAPSHOT
  local clean="${version%-SNAPSHOT}"
  
  # Sépare les composants de version
  IFS='.' read -r -a parts <<< "$clean"
  
  # Assure-toi qu'il y a 3 composants (major.minor.patch)
  while [[ ${#parts[@]} -lt 3 ]]; do 
    parts+=("0")
  done
  
  # Incrémente selon le type
  case "$bump_type" in
    major) 
      parts[0]=$((parts[0]+1))
      parts[1]=0
      parts[2]=0 
      ;;
    minor) 
      parts[1]=$((parts[1]+1))
      parts[2]=0 
      ;;
    patch) 
      parts[2]=$((parts[2]+1)) 
      ;;
    *) 
      echo "::error::$MSG_ERROR_INVALID_BUMP: $bump_type" >&2
      return $EXIT_INVALID_BUMP 
      ;;
  esac
  
  # Reconstitue la version
  echo "${parts[0]}.${parts[1]}.${parts[2]}"
}

# Calcule le code de version numérique
calculate_version_code() {
  local major="$1" minor="$2" patch="$3"
  # Formule standard: major * 10000 + minor * 100 + patch
  # Le préfixe 10# force l'interprétation en base 10 pour éviter les problèmes avec les zéros en préfixe
  echo $((10#$major*10000 + 10#$minor*100 + 10#$patch))
}

# =====================================================================
# FONCTIONS DE PARSING JSON
# =====================================================================

# Extrait une valeur simple d'une chaîne JSON
parse_json_value() {
  local json="$1" key="$2" val
  
  # Essaie d'abord avec le nom exact de la clé
  val=$(echo "$json" | grep -o "\"$key\"[^,}]*" | cut -d':' -f2- | tr -d ' "' || echo "")
  
  # Si rien n'est trouvé, essaie avec la version kebab-case
  if [[ -z "$val" ]]; then
    local kebab
    kebab=$(echo "$key" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')
    val=$(echo "$json" | grep -o "\"$kebab\"[^,}]*" | cut -d':' -f2- | tr -d ' "' || echo "")
  fi
  
  echo "$val"
}

# Extrait les valeurs JSON en utilisant jq (pour les JSON complexes)
extract_with_jq() {
  local json="$1"
  local config=()
  
  # Détecte si le JSON est complexe
  local is_complex
  is_complex=$(jq 'any(values|type=="object" or type=="array")' <<<"$json" 2>/dev/null || echo "false")
  [[ "$is_complex" == "true" ]] && echo "::notice::JSON complexe détecté, utilisation de jq pour le parsing"
  
  # Extraction avec jq
  config[0]=$(jq -r '.gradlePropertiesPath // .["gradle-properties-path"] // empty' <<<"$json" 2>/dev/null || echo "")
  config[1]=$(jq -r '.versionFilePath // .["version-file-path"] // empty' <<<"$json" 2>/dev/null || echo "")
  config[2]=$(jq -r '.customVersion // .["custom-version"] // empty' <<<"$json" 2>/dev/null || echo "")
  config[3]=$(jq -r '.snapshot // empty' <<<"$json" 2>/dev/null || echo "")
  config[4]=$(jq -r '.versionPrefix // .["version-prefix"] // empty' <<<"$json" 2>/dev/null || echo "")
  config[5]=$(jq -r '.bump // empty' <<<"$json" 2>/dev/null || echo "")
  config[6]=$(jq -r '.productionBranches // .["production-branches"] // empty' <<<"$json" 2>/dev/null || echo "")
  
  # Renvoie les valeurs en séparant par un délimiteur
  echo "${config[0]:-}||${config[1]:-}||${config[2]:-}||${config[3]:-}||${config[4]:-}||${config[5]:-}||${config[6]:-}"
}

# Extrait les valeurs JSON avec une méthode simple (pour les JSON simples)
extract_without_jq() {
  local json="$1"
  local config=()
  
  echo "::warning::$MSG_WARNING_NO_JQ"
  
  # Vérifier que le JSON n'est pas complexe
  if [[ "$json" =~ [{\[].*[{\[] ]]; then
    echo "::error::$MSG_ERROR_JQ_REQUIRED" >&2
    exit $EXIT_DEPENDENCY_MISSING
  fi
  
  # Extraction avec méthode simple
  local val
  val=$(parse_json_value "$json" "gradlePropertiesPath"); [[ -n "$val" ]] && config[0]="$val"
  val=$(parse_json_value "$json" "versionFilePath");      [[ -n "$val" ]] && config[1]="$val"
  val=$(parse_json_value "$json" "customVersion");        [[ -n "$val" ]] && config[2]="$val"
  val=$(parse_json_value "$json" "snapshot");             [[ -n "$val" ]] && config[3]="$val"
  val=$(parse_json_value "$json" "versionPrefix");        [[ -n "$val" ]] && config[4]="$val"
  val=$(parse_json_value "$json" "bump");                 [[ -n "$val" ]] && config[5]="$val"
  val=$(parse_json_value "$json" "productionBranches");   [[ -n "$val" ]] && config[6]="$val"
  
  # Renvoie les valeurs en séparant par un délimiteur
  echo "${config[0]:-}||${config[1]:-}||${config[2]:-}||${config[3]:-}||${config[4]:-}||${config[5]:-}||${config[6]:-}"
}

# Parse le JSON de configuration
parse_config_json() {
  local json="$1" has_jq_flag="$2"
  
  echo "$MSG_USING_JSON"
  
  if [[ "$has_jq_flag" == "true" ]]; then
    extract_with_jq "$json"
  else
    extract_without_jq "$json"
  fi
}

# =====================================================================
# FONCTION PRINCIPALE DE GESTION DU MODE DRY-RUN
# =====================================================================

# Traite le mode dry-run, écrit des valeurs factices et sort
handle_dry_run() {
  echo "::notice::$MSG_MODE_DRYRUN"
  
  local build_date git_commit
  build_date=$(get_build_date)
  git_commit=$(get_git_commit)
  
  # Écrit des valeurs factices
  write_output "version"      "v0.0.0-DRYRUN"
  write_output "version_name" "0.0.0-DRYRUN"
  write_output "version_code" "0"
  write_output "major"        "0"
  write_output "minor"        "0"
  write_output "patch"        "0"
  write_output "is_snapshot"  "true"
  write_output "is_release"   "false"
  write_output "build_date"   "$build_date"
  write_output "git_commit"   "$git_commit"
  
  exit $EXIT_SUCCESS
}

# =====================================================================
# FONCTION PRINCIPALE
# =====================================================================

main() {
  # Vérifie si l'aide est demandée
  [[ "${1:-}" == "--help" ]] && { usage; exit $EXIT_SUCCESS; }
  
  # Gère le mode dry-run
  [[ "${DRY_RUN:-false}" == "true" ]] && handle_dry_run
  
  # Vérifie les dépendances critiques
  validate_dependencies
  
  # Vérifie si jq est disponible
  local has_jq_value
  has_jq_value=$(has_jq)
  
  # Défini les valeurs par défaut
  local gradle_properties_path="${GRADLE_PROPERTIES_PATH:-$DEFAULT_GRADLE_PATH}"
  local version_file_path="${VERSION_FILE_PATH:-$DEFAULT_VERSION_KT_PATH}"
  local custom_version="${CUSTOM_VERSION:-}"
  local snapshot_mode="${SNAPSHOT_MODE:-auto}"
  local version_prefix="${VERSION_PREFIX:-$DEFAULT_VERSION_PREFIX}"
  local bump="${BUMP:-}"
  local production_branches="${PRODUCTION_BRANCHES:-$DEFAULT_PRODUCTION_BRANCHES}"
  
  # Valide les paramètres d'entrée
  validate_input_params "$snapshot_mode" "$bump"
  
  # Traite la configuration JSON si fournie
  if [[ -n "${CONFIG_JSON:-}" ]]; then
    local config_values
    config_values=$(parse_config_json "$CONFIG_JSON" "$has_jq_value")
    
    # Sépare les valeurs extraites
    IFS='||' read -r gpp vfp cv sm vp b pb <<< "$config_values"
    
    # Mise à jour des paramètres si des valeurs sont présentes
    [[ -n "$gpp" ]] && gradle_properties_path="$gpp"
    [[ -n "$vfp" ]] && version_file_path="$vfp"
    [[ -n "$cv" ]] && custom_version="$cv"
    [[ -n "$sm" ]] && snapshot_mode="$sm"
    [[ -n "$vp" ]] && version_prefix="$vp"
    [[ -n "$b" ]] && bump="$b"
    [[ -n "$pb" ]] && production_branches="$pb"
    
    # Revalide les paramètres après traitement JSON
    validate_input_params "$snapshot_mode" "$bump"
  fi
  
  # Exporte les branches de production (pour is_production_branch)
  export PRODUCTION_BRANCHES="$production_branches"
  
  # Vérifie si les fichiers source existent
  if [[ -z "$custom_version" && ! -f "$gradle_properties_path" && ! -f "$version_file_path" ]]; then
    echo "::error::$MSG_ERROR_MISSING_FILES"
    exit $EXIT_GENERAL_ERROR
  fi
  
  # Extrait la version
  local version
  if [[ -n "$custom_version" ]]; then
    version="$custom_version"
    echo "$MSG_USING_CUSTOM: $version"
  else
    if [[ -f "$gradle_properties_path" ]]; then
      version=$(extract_from_gradle_properties "$gradle_properties_path")
      [[ -n "$version" ]] && echo "$MSG_EXTRACTED_GRADLE: $version"
    fi
    
    if [[ -z "$version" && -f "$version_file_path" ]]; then
      version=$(extract_from_versions_kt "$version_file_path")
      [[ -n "$version" ]] && echo "$MSG_EXTRACTED_KOTLIN: $version"
    fi
    
    if [[ -z "$version" ]]; then
      echo "::error::$MSG_ERROR_NO_VERSION"
      exit $EXIT_GENERAL_ERROR
    fi
  fi
  
  # Nettoie la version
  version=${version//[\"\' ]/}
  validate_version_format "$version" || exit $?
  
  # Applique le bump si demandé
  if [[ -n "$bump" ]]; then
    version=$(bump_version "$version" "$bump") || exit $?
    echo "$MSG_VERSION_AFTER_BUMP ($bump): $version"
    validate_version_format "$version" || exit $?
  fi
  
  # Extrait les composants de la version
  local vs="${version%-SNAPSHOT}"
  IFS='.' read -r -a parts <<<"$vs"
  while [[ ${#parts[@]} -lt 3 ]]; do parts+=("0"); done
  
  local major="${parts[0]}" minor="${parts[1]}" patch="${parts[2]}"
  local version_code
  version_code=$(calculate_version_code "$major" "$minor" "$patch")
  
  # Détermine si c'est un snapshot
  local is_snapshot="false"
  case "$snapshot_mode" in
    true)  is_snapshot="true" ;;
    false) is_snapshot="false" ;;
    auto)  is_snapshot=$(is_snapshot_auto "$version") ;;
    *)     
      echo "::warning::$MSG_WARNING_SNAPSHOT: $snapshot_mode"
      is_snapshot=$(is_snapshot_auto "$version") 
      ;;
  esac
  
  # Construit le nom de version final
  local version_name="$vs"
  if [[ "$is_snapshot" == "true" && "$version" != *"-SNAPSHOT"* ]]; then
    version_name+="-SNAPSHOT"
  elif [[ "$is_snapshot" == "false" && "$version" == *"-SNAPSHOT"* ]]; then
    version_name="$vs"
  fi
  
  local full_version="${version_prefix}${version_name}"
  local is_release=$([[ "$is_snapshot" == "false" ]] && echo "true" || echo "false")
  
  # Prépare des valeurs additionnelles
  local build_date git_commit
  build_date=$(get_build_date)
  git_commit=$(get_git_commit)
  
  # Écrit les sorties
  write_output "version"      "$full_version"
  write_output "version_name" "$version_name"
  write_output "version_code" "$version_code"
  write_output "major"        "$major"
  write_output "minor"        "$minor"
  write_output "patch"        "$patch"
  write_output "is_snapshot"  "$is_snapshot"
  write_output "is_release"   "$is_release"
  write_output "build_date"   "$build_date"
  write_output "git_commit"   "$git_commit"
  
  # Affiche le résumé
  echo "$MSG_FINAL_VERSION: $full_version"
  echo "$MSG_FINAL_CODE: $version_code"
  echo "$MSG_FINAL_SNAPSHOT: $is_snapshot"
  echo "$MSG_FINAL_RELEASE: $is_release"
  
  return $EXIT_SUCCESS
}

# Exécute main si lancé, pas si sourcé
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

# =====================================================================
# NOTES POUR L'IMPLÉMENTATION DES TESTS
# =====================================================================
# Recommendation: Créez un répertoire tests/ avec la structure suivante:
#
# tests/
# ├── fixtures/
# │   ├── gradle.properties     # Exemple avec version=1.2.3
# │   ├── Versions.kt           # Exemple avec val APP_VERSION = "2.3.4"
# │   ├── invalid.properties    # Fichier sans version valide
# │   └── config.json           # Exemple de JSON de configuration
# ├── test_extraction.bats      # Tests d'extraction de version
# ├── test_snapshot.bats        # Tests de mode snapshot
# ├── test_bump.bats            # Tests d'incrémentation de version
# └── test_json.bats            # Tests de parsing JSON
#
# Installer bats: https://github.com/bats-core/bats-core
# Pour CI, utiliser: github.com/bats-core/bats-action
#
# Exemple de test:
# @test "Extraction depuis gradle.properties" {
#   export GRADLE_PROPERTIES_PATH="./tests/fixtures/gradle.properties"
#   run ./version-info.sh
#   [ "$status" -eq 0 ]
#   [[ "$output" == *"1.2.3"* ]]
# }
#
# Intégrer ShellCheck dans votre CI avec:
# - name: Run ShellCheck
#   uses: ludeeus/action-shellcheck@master
#   with:
#     scandir: './'
#     severity: 'warning'