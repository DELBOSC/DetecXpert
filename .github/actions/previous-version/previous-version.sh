#!/bin/bash
# ==============================================================================
# previous-version.sh
# 
# Script d'extraction de la version précédente pour l'application DetectXpert
# Utilisé par l'action GitHub .github/actions/previous-version
#
# UTILISATION: 
#   ./previous-version.sh [--help] [--offline] [--test]
#
# OPTIONS:
#   --help     Affiche ce message d'aide
#   --offline  Force l'utilisation des tags git, même si VERSION_SOURCE=releases
#   --test     Exécute les tests intégrés pour valider les fonctions SemVer
#
# VARIABLES D'ENVIRONNEMENT:
#   GITHUB_TOKEN         - Token d'authentification GitHub (obligatoire)
#   VERSION_PATTERN      - Expression régulière pour filtrer les versions
#   EXCLUDE_PRE_RELEASES - Exclure les versions pre-release (true/false)
#   EXCLUDE_DRAFTS       - Exclure les releases en mode brouillon (true/false)
#   VERSION_SOURCE       - Source des versions: tags, releases ou package
#   VERSION_LIMIT        - Nombre maximum de versions à analyser (0 = pas de limite)
#   CURRENT_VERSION      - Version actuelle pour trouver la précédente
#   FALLBACK_VERSION     - Version par défaut si aucune trouvée
#   PRODUCT_FLAVOR       - Variante de produit (premium, standard, etc.)
#   COMPARE_BRANCH       - Branche de comparaison (main, develop, etc.)
#   SKIP_JQ_CHECK        - Ignorer la vérification de jq (true/false)
#   SCRIPT_DEBUG         - Mode debug (true/false)
#   LOG_FORMAT           - Format de logs (text/json)
#   GITHUB_OUTPUT        - Fichier où écrire les outputs (défini par GitHub Actions)
#
# SORTIES: 
#   Renseigne les variables dans $GITHUB_OUTPUT pour l'action GitHub
# ==============================================================================

set -eo pipefail

# ==============================================================================
# TRAITEMENT DES ARGUMENTS ET INITIALISATION
# ==============================================================================

# Initialisation des variables globales
OFFLINE_MODE="false"
EXECUTE_TESTS="false"

# Traitement des arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      grep '^# ' "$0" | grep -v '^#!/bin/bash' | sed 's/^# \?//'
      exit 0
      ;;
    --offline)
      OFFLINE_MODE="true"
      shift
      ;;
    --test)
      EXECUTE_TESTS="true"
      shift
      ;;
    *)
      echo "[ERROR] Option non reconnue: $1" >&2
      echo "Utilisez --help pour afficher les options disponibles" >&2
      exit 1
      ;;
  esac
done

# Cache pour les versions normalisées
declare -A VERSION_CACHE

# ==============================================================================
# FONCTIONS UTILITAIRES DE BASE
# ==============================================================================

function initialize_environment_variables() {
  # Définition des variables par défaut
  : "${GITHUB_TOKEN:?GITHUB_TOKEN est requis. Veuillez fournir un token valide.}"
  : "${GITHUB_API_URL:=https://api.github.com}"
  : "${GITHUB_SERVER_URL:=https://github.com}"
  : "${VERSION_SOURCE:=releases}"
  : "${VERSION_PATTERN:=v[0-9]+\.[0-9]+\.[0-9]+.*}"
  : "${EXCLUDE_PRE_RELEASES:=true}"
  : "${EXCLUDE_DRAFTS:=true}"
  : "${VERSION_LIMIT:=0}"  # 0 = pas de limite (avec un maximum raisonnable)
  : "${FALLBACK_VERSION:=v0.0.0}"
  : "${COMPARE_BRANCH:=main}"
  : "${SKIP_JQ_CHECK:=false}"
  : "${SCRIPT_DEBUG:=false}"
  : "${LOG_FORMAT:=text}"  # text ou json
  
  # Si GITHUB_OUTPUT est défini, vérifier qu'il est écrivable
  if [[ -n "${GITHUB_OUTPUT}" ]]; then
    if ! touch "${GITHUB_OUTPUT}" 2>/dev/null; then
      error "GITHUB_OUTPUT est défini mais n'est pas écrivable: ${GITHUB_OUTPUT}"
    fi
  fi
  
  # Activer le mode debug si demandé
  if [[ "${SCRIPT_DEBUG}" == "true" ]]; then
    set -x
  fi
}

function log() {
  local message="$1"
  local level="${2:-INFO}"
  
  if [[ "${LOG_FORMAT}" == "json" ]]; then
    # Échapper les guillemets pour JSON
    local escaped_message=$(echo "$message" | sed 's/"/\\"/g')
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"level\":\"$level\",\"message\":\"$escaped_message\"}"
  else
    echo "[$level] $message"
  fi
}

function warn() {
  log "$1" "WARN" >&2
}

function error() {
  log "$1" "ERROR" >&2
  exit 1
}

function debug() {
  if [[ "${SCRIPT_DEBUG}" == "true" ]]; then
    log "$1" "DEBUG"
  fi
}

function set_output() {
  local name="$1"
  local value="$2"
  
  # Vérifier si GITHUB_OUTPUT est défini (en environnement GitHub Actions)
  if [[ -n "${GITHUB_OUTPUT}" ]]; then
    # Gérer les valeurs multi-lignes en utilisant la syntaxe délimiteur
    if [[ "$value" == *$'\n'* ]]; then
      {
        echo "$name<<EOF"
        echo "$value"
        echo "EOF"
      } >> "${GITHUB_OUTPUT}"
    else
      echo "$name=$value" >> "${GITHUB_OUTPUT}"
    fi
    debug "Output défini dans GITHUB_OUTPUT: $name"
  else
    # En local, afficher simplement les valeurs
    echo "OUTPUT: $name=$value"
  fi
}

function validate_inputs() {
  # Validation des valeurs booléennes
  for var_name in EXCLUDE_PRE_RELEASES EXCLUDE_DRAFTS SKIP_JQ_CHECK SCRIPT_DEBUG OFFLINE_MODE; do
    if [[ -n "${!var_name}" ]]; then
      var_value="${!var_name}"
      if [[ "${var_value}" != "true" && "${var_value}" != "false" ]]; then
        error "${var_name} doit être 'true' ou 'false'. Valeur reçue: ${var_value}"
      fi
    fi
  done
  
  # Validation numérique
  if [[ -n "${VERSION_LIMIT}" ]] && ! [[ "${VERSION_LIMIT}" =~ ^[0-9]+$ ]]; then
    error "VERSION_LIMIT doit être un entier positif. Valeur reçue: ${VERSION_LIMIT}"
  fi
  
  # Validation du pattern
  if ! echo "test" | grep -E "${VERSION_PATTERN}" &>/dev/null && [[ -n "${VERSION_PATTERN}" ]]; then
    error "VERSION_PATTERN n'est pas une expression régulière valide: ${VERSION_PATTERN}"
  fi
  
  # Validation de VERSION_SOURCE
  if [[ "${VERSION_SOURCE}" != "tags" && "${VERSION_SOURCE}" != "releases" && "${VERSION_SOURCE}" != "package" ]]; then
    error "VERSION_SOURCE doit être 'tags', 'releases' ou 'package'. Valeur reçue: ${VERSION_SOURCE}"
  fi
  
  # Validation de LOG_FORMAT
  if [[ "${LOG_FORMAT}" != "text" && "${LOG_FORMAT}" != "json" ]]; then
    error "LOG_FORMAT doit être 'text' ou 'json'. Valeur reçue: ${LOG_FORMAT}"
  fi
  
  # Validation de CURRENT_VERSION si défini
  if [[ -n "${CURRENT_VERSION}" ]]; then
    # Vérifier que CURRENT_VERSION respecte le pattern semver de base
    if ! [[ "${CURRENT_VERSION}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
      warn "CURRENT_VERSION ne semble pas respecter le format SemVer standard: ${CURRENT_VERSION}"
    fi
    
    # Vérifier que CURRENT_VERSION respecte le pattern demandé
    if ! echo "${CURRENT_VERSION}" | grep -E "${VERSION_PATTERN}" &>/dev/null; then
      warn "CURRENT_VERSION ne correspond pas au pattern VERSION_PATTERN: ${CURRENT_VERSION} vs ${VERSION_PATTERN}"
    fi
  fi
}

function check_requirements() {
  # Vérification des dépendances obligatoires
  if ! command -v git &> /dev/null; then
    error "git est requis mais non installé."
  fi
  
  # Vérification de jq seulement si SKIP_JQ_CHECK n'est pas true et pas en mode offline pour releases
  if [[ "${SKIP_JQ_CHECK}" != "true" && ! (${OFFLINE_MODE} == "true" && ${VERSION_SOURCE} == "releases") ]]; then
    if ! command -v jq &> /dev/null; then
      error "jq est requis mais non installé. Veuillez installer jq, utiliser azukiapp/jq-action@v1, ou activer SKIP_JQ_CHECK."
    fi
  else
    debug "Vérification de jq ignorée"
  fi
}

function initialize_repo_info() {
  # Initialisation des informations sur le dépôt
  REPO_OWNER=""
  REPO_NAME=""
  
  # Essayer d'extraire à partir de GITHUB_REPOSITORY
  if [[ -n "${GITHUB_REPOSITORY}" ]]; then
    if [[ "${GITHUB_REPOSITORY}" =~ ([^/]+)/([^/]+) ]]; then
      REPO_OWNER="${BASH_REMATCH[1]}"
      REPO_NAME="${BASH_REMATCH[2]}"
      # Supprimer le .git à la fin du nom si présent
      REPO_NAME="${REPO_NAME%.git}"
      debug "Dépôt extrait de GITHUB_REPOSITORY: ${REPO_OWNER}/${REPO_NAME}"
      return 0
    fi
  fi
  
  # Essayer d'extraire à partir de git remote
  local remote_url=$(git config --get remote.origin.url)
  if [[ -n "${remote_url}" ]]; then
    # Formats possibles:
    # https://github.com/owner/repo.git
    # git@github.com:owner/repo.git
    if [[ "${remote_url}" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
      REPO_OWNER="${BASH_REMATCH[1]}"
      REPO_NAME="${BASH_REMATCH[2]%.git}" # Supprimer .git si présent
      debug "Dépôt extrait de git remote: ${REPO_OWNER}/${REPO_NAME}"
      return 0
    fi
  fi
  
  # Si on est en mode offline et qu'on utilise les tags, ne pas erreur
  if [[ "${OFFLINE_MODE}" == "true" && "${VERSION_SOURCE}" == "tags" ]]; then
    warn "Impossible de déterminer le dépôt GitHub, mais le mode offline avec tags ne l'exige pas."
    return 0
  fi
  
  error "Impossible de déterminer le dépôt GitHub. Veuillez définir GITHUB_REPOSITORY ou configurer git remote.origin.url correctement."
}

# ==============================================================================
# FONCTIONS SEMVER
# ==============================================================================

# Parse une version semver en composants dans un format facile à comparer
# Utilise le cache si la version a déjà été normalisée
function normalize_version() {
  local version="$1"
  
  # Vérifier si la version est déjà dans le cache
  if [[ -n "${VERSION_CACHE[$version]}" ]]; then
    echo "${VERSION_CACHE[$version]}"
    return
  fi
  
  local normalized_version
  
  # Retirer les préfixes communs
  normalized_version="${version#v}"
  normalized_version="${normalized_version#release-}"
  
  # Support pour les versions semver (majeur.mineur.patch-prerelease+build)
  if [[ "$normalized_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([^+]*))?(\+(.*))?$ ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    local prerelease="${BASH_REMATCH[5]}"
    local buildmeta="${BASH_REMATCH[7]}"
    
    # Padding avec des zéros pour tri lexicographique
    # Ajouter ~ pour les versions sans prerelease (qui sont considérées supérieures)
    local result
    result=$(printf "%08d %08d %08d %s %s" "$major" "$minor" "$patch" "${prerelease:-"~"}" "${buildmeta:-""}")
    
    # Stocker dans le cache
    VERSION_CACHE[$version]="$result"
    
    echo "$result"
  else
    # Fallback pour les formats non-semver
    echo "$normalized_version"
  fi
}

# Convertit une prerelease en format comparable
# Pour gérer correctement alpha.1 vs alpha.10
function normalize_prerelease() {
  local prerelease="$1"
  local result=""
  
  # Diviser par les points
  IFS='.' read -ra parts <<< "$prerelease"
  
  for part in "${parts[@]}"; do
    # Si la partie est numérique, ajuster avec padding
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      result="${result}.$(printf "%08d" "$part")"
    else
      result="${result}.${part}"
    fi
  done
  
  # Supprimer le premier point
  echo "${result#.}"
}

# Compare deux versions semver et retourne 1 (v1>v2), 0 (v1=v2), -1 (v1<v2)
function compare_versions() {
  local v1="$1"
  local v2="$2"
  
  # Normaliser les versions (utilise le cache si disponible)
  local v1_norm=$(normalize_version "$v1")
  local v2_norm=$(normalize_version "$v2")
  
  # Extraire les composants
  read -r v1_major v1_minor v1_patch v1_prerelease v1_build <<< "$v1_norm"
  read -r v2_major v2_minor v2_patch v2_prerelease v2_build <<< "$v2_norm"
  
  # Comparaison numérique pour majeur, mineur, patch
  if (( 10#$v1_major > 10#$v2_major )); then
    echo "1"
    return
  elif (( 10#$v1_major < 10#$v2_major )); then
    echo "-1"
    return
  fi
  
  if (( 10#$v1_minor > 10#$v2_minor )); then
    echo "1"
    return
  elif (( 10#$v1_minor < 10#$v2_minor )); then
    echo "-1"
    return
  fi
  
  if (( 10#$v1_patch > 10#$v2_patch )); then
    echo "1"
    return
  elif (( 10#$v1_patch < 10#$v2_patch )); then
    echo "-1"
    return
  fi
  
  # À ce stade, la version de base est identique, on compare les pre-releases
  # Une version sans pre-release est considérée plus récente qu'une avec pre-release
  if [[ "$v1_prerelease" == "~" && "$v2_prerelease" != "~" ]]; then
    echo "1"
    return
  elif [[ "$v1_prerelease" != "~" && "$v2_prerelease" == "~" ]]; then
    echo "-1"
    return
  elif [[ "$v1_prerelease" != "~" && "$v2_prerelease" != "~" ]]; then
    # Normaliser les pre-releases pour gérer correctement alpha.1 vs alpha.10
    local v1_pre_norm=$(normalize_prerelease "$v1_prerelease")
    local v2_pre_norm=$(normalize_prerelease "$v2_prerelease")
    
    # Comparaison lexicographique des pre-releases normalisées
    if [[ "$v1_pre_norm" > "$v2_pre_norm" ]]; then
      echo "1"
      return
    elif [[ "$v1_pre_norm" < "$v2_pre_norm" ]]; then
      echo "-1"
      return
    fi
  fi
  
  # Les versions sont identiques (on ignore les métadonnées de build par défaut)
  echo "0"
}

function is_pre_release() {
  local version="$1"
  
  # Normaliser la version (utilise le cache si disponible)
  local normalized=$(normalize_version "$version")
  
  # Vérifier si elle contient une partie pre-release
  read -r _ _ _ prerelease _ <<< "$normalized"
  
  if [[ "$prerelease" != "~" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

function version_matches_flavor() {
  local version="$1"
  local flavor="${PRODUCT_FLAVOR}"
  
  # Si aucune saveur n'est spécifiée, toutes les versions sont acceptées
  if [[ -z "$flavor" ]]; then
    echo "true"
    return
  fi
  
  # Échapper les caractères spéciaux pour la regex
  local escaped_flavor=$(echo "$flavor" | sed 's/\./\\./g' | sed 's/\-/\\-/g')
  
  # Logique pour déterminer si la version correspond à la saveur spécifiée
  # Exemple: version v1.2.3-premium pour la saveur premium
  if [[ "$version" =~ [-_.+]${escaped_flavor}([-_.+]|$) ]]; then
    echo "true"
  else
    echo "false"
  fi
}

function extract_semver_components() {
  local version="$1"
  
  # Retirer le préfixe 'v' si présent
  local clean_version="${version#v}"
  
  # Pattern semver standard
  if [[ "$clean_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([^+]*))?(\+(.*))?$ ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    local prerelease="${BASH_REMATCH[5]}"
    local buildmeta="${BASH_REMATCH[7]}"
    
    # Retourner les composants
    echo "$major" "$minor" "$patch" "$prerelease" "$buildmeta"
  else
    # Fallback pour les versions non-conformes
    warn "La version $version n'est pas au format semver standard"
    echo "0" "0" "0" "" ""
  fi
}

# ==============================================================================
# FONCTIONS GITHUB API
# ==============================================================================

function github_api_request() {
  local endpoint="$1"
  local method="${2:-GET}"
  local data="$3"
  local max_retries="${4:-3}"
  local retry_delay="${5:-2}"
  
  local url="${GITHUB_API_URL}${endpoint}"
  local headers=(
    -H "Authorization: token ${GITHUB_TOKEN}" 
    -H "Accept: application/vnd.github.v3+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )
  local curl_opts=(
    --silent
    --fail-with-body
    --retry $max_retries
    --retry-delay $retry_delay
    --connect-timeout 10
    --max-time 30
  )
  
  if [[ "$method" == "POST" && -n "$data" ]]; then
    headers+=(-H "Content-Type: application/json")
    curl_opts+=(--data "$data")
  fi
  
  debug "API Request: $method $url"
  local response
  local status=0
  
  # Capturer à la fois la sortie et le code d'erreur, rediriger stderr pour éviter d'exposer le token
  response=$(curl "${curl_opts[@]}" "${headers[@]}" -X "$method" "$url" 2>/dev/null) || status=$?
  
  # Gérer les erreurs spécifiques
  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 22 && "$response" == *"404 Not Found"* ]]; then
      # 404 - Tag ou release non trouvé, retourner un résultat vide sans erreur
      debug "Ressource non trouvée (404): $url"
      echo "{}"
      return 0
    elif [[ $status -eq 22 && "$response" == *"503 Service Unavailable"* || "$response" == *"502 Bad Gateway"* ]]; then
      # Erreur de service, essayer de nouveau avec un délai plus long
      warn "Service GitHub temporairement indisponible (5xx). Nouvel essai avec délai étendu..."
      sleep 5
      response=$(curl "${curl_opts[@]}" "${headers[@]}" -X "$method" "$url" 2>/dev/null) || status=$?
      
      if [[ $status -ne 0 ]]; then
        # Si en mode offline ou avec source=tags, suggérer le fallback
        if [[ "${VERSION_SOURCE}" == "releases" ]]; then
          warn "Échec persistant de l'API GitHub. Utilisation de git tags comme fallback."
          echo "FALLBACK_TO_TAGS=true"
          return 0
        else
          error "Échec persistant de la requête GitHub API: $method $url (code $status)"
        fi
      fi
    else
      local safe_response=$(echo "$response" | sed 's/Authorization:.*token.*/Authorization: REDACTED/g')
      error "Échec de la requête GitHub API: $method $url (code $status): ${safe_response:0:200}..."
    fi
  fi
  
  echo "$response"
}

function get_github_releases() {
  local page=1
  local per_page=30  # Maximum autorisé par GitHub API
  local all_releases=()
  local total_releases=0
  local limit="${VERSION_LIMIT}"
  
  # Si limit=0, utiliser une valeur raisonnable comme max (100)
  if [[ $limit -eq 0 ]]; then
    limit=100
  fi
  
  # Parcourir toutes les pages nécessaires
  while [[ $total_releases -lt $limit ]]; do
    debug "Récupération des releases page $page (per_page=$per_page)"
    
    local releases_data
    releases_data=$(github_api_request "/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=${per_page}&page=${page}")
    
    # Vérifier si on doit fallback aux tags
    if [[ "$releases_data" == "FALLBACK_TO_TAGS=true" ]]; then
      debug "Fallback aux tags demandé"
      echo "FALLBACK_TO_TAGS"
      return
    fi
    
    # Vérifier si on a obtenu des résultats
    local page_releases
    page_releases=$(echo "$releases_data" | jq '. | length')
    
    if [[ $page_releases -eq 0 ]]; then
      # Plus de releases à récupérer
      break
    fi
    
    # Concaténer les résultats
    all_releases+=("$releases_data")
    
    # Incrémenter le nombre total et la page
    total_releases=$((total_releases + page_releases))
    page=$((page + 1))
    
    # Vérifier si on a atteint la limite ou s'il n'y a plus de données (dernière page)
    if [[ $total_releases -ge $limit || $page_releases -lt $per_page ]]; then
      break
    fi
  done
  
  # Combiner les résultats et limiter au nombre demandé
  if [[ ${#all_releases[@]} -gt 0 ]]; then
    echo "${all_releases[@]}" | jq -s 'add | .[0:'"$limit"']'
  else
    echo "[]"
  fi
}

function get_version_date() {
  local version="$1"
  local source="$2"
  
  if [[ "$source" == "tags" ]]; then
    # Récupérer la date du tag depuis git
    local tag_date
    tag_date=$(git show-ref -d "$version" | cut -d' ' -f1 | xargs git show --format=%aI --quiet 2>/dev/null || echo "")
    echo "$tag_date"
  elif [[ "$source" == "releases" ]]; then
    # Utiliser l'API GitHub pour récupérer la date de la release
    local release_data
    release_data=$(github_api_request "/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${version}")
    
    # Vérifier si on doit fallback aux tags
    if [[ "$release_data" == "FALLBACK_TO_TAGS=true" ]]; then
      # Essayer de récupérer la date à partir des tags
      get_version_date "$version" "tags"
      return
    fi
    
    local release_date
    release_date=$(echo "$release_data" | jq -r '.published_at // .created_at // ""')
    echo "$release_date"
  else
    echo ""
  fi
}

function count_commits_since() {
  local version="$1"
  local branch="${COMPARE_BRANCH}"
  
  # Compter les commits entre le tag et HEAD sur la branche spécifiée
  local commit_count
  commit_count=$(git rev-list --count "${version}..${branch}" 2>/dev/null || echo "0")
  echo "$commit_count"
}

function get_changelog_url() {
  local version="$1"
  
  # Récupérer l'URL du changelog depuis la release sur GitHub
  if [[ "${VERSION_SOURCE}" == "releases" && "${OFFLINE_MODE}" != "true" ]]; then
    local release_data
    release_data=$(github_api_request "/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${version}")
    
    # Vérifier si on doit fallback aux tags
    if [[ "$release_data" == "FALLBACK_TO_TAGS=true" ]]; then
      # Pour les tags, construire l'URL GitHub standard
      echo "${GITHUB_SERVER_URL}/${REPO_OWNER}/${REPO_NAME}/releases/tag/${version}"
      return
    fi
    
    local html_url
    html_url=$(echo "$release_data" | jq -r '.html_url // ""')
    echo "$html_url"
  else
    # Pour les tags, construire l'URL GitHub standard
    echo "${GITHUB_SERVER_URL}/${REPO_OWNER}/${REPO_NAME}/releases/tag/${version}"
  fi
}

function get_release_id() {
  local version="$1"
  
  if [[ "${VERSION_SOURCE}" == "releases" && "${OFFLINE_MODE}" != "true" && -n "$version" ]]; then
    local release_data
    release_data=$(github_api_request "/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${version}")
    
    # Vérifier si on doit fallback aux tags
    if [[ "$release_data" == "FALLBACK_TO_TAGS=true" ]]; then
      return
    fi
    
    local release_id
    release_id=$(echo "$release_data" | jq -r '.id // ""')
    echo "$release_id"
  else
    echo ""
  fi
}

# ==============================================================================
# FONCTIONS D'EXTRACTION DE VERSIONS
# ==============================================================================

function get_previous_version_from_tags() {
  local current_version="${CURRENT_VERSION}"
  local pattern="${VERSION_PATTERN}"
  local exclude_pre_releases="${EXCLUDE_PRE_RELEASES}"
  local limit="${VERSION_LIMIT}"
  local flavor="${PRODUCT_FLAVOR}"
  
  # Si limit=0, pas de limite (utilisation d'une valeur max raisonnable)
  if [[ $limit -eq 0 ]]; then
    limit=9999
  fi
  
  # Récupérer tous les tags
  local all_tags
  all_tags=$(git tag -l)
  
  # Tableau pour stocker [version_normalisée|tag]
  local tag_info=()
  
  # Filtrer les tags correspondant au pattern et à la saveur
  while IFS= read -r tag; do
    # Ignorer les lignes vides
    [[ -z "$tag" ]] && continue
    
    # Vérifier le pattern
    if ! echo "$tag" | grep -E "$pattern" &>/dev/null; then
      debug "Tag $tag ignoré: ne correspond pas au pattern $pattern"
      continue
    fi
    
    # Vérifier la saveur
    if [[ -n "$flavor" ]] && [[ "$(version_matches_flavor "$tag")" != "true" ]]; then
      debug "Tag $tag ignoré: ne correspond pas à la saveur $flavor"
      continue
    fi
    
    # Vérifier si c'est une pre-release
    if [[ "$exclude_pre_releases" == "true" ]]; then
      local is_pre
      is_pre=$(is_pre_release "$tag")
      if [[ "$is_pre" == "true" ]]; then
        debug "Tag $tag ignoré: c'est une pre-release"
        continue
      fi
    fi
    
    # Normaliser le tag et stocker l'association
    local norm_version
    norm_version=$(normalize_version "$tag")
    tag_info+=("$norm_version|$tag")
  done <<< "$all_tags"
  
  # Vérifier si des tags ont été trouvés
  if [[ ${#tag_info[@]} -eq 0 ]]; then
    debug "Aucun tag correspondant trouvé"
    echo ""
    return
  fi
  
  # Trier les tags par version normalisée (du plus récent au plus ancien)
  local sorted_tags
  # shellcheck disable=SC2207
  IFS=$'\n' sorted_tags=($(for t in "${tag_info[@]}"; do echo "$t"; done | sort -r))
  unset IFS
  
  debug "Tags triés: ${sorted_tags[*]}"
  
  # Convertir en tableau de tags réels (sans la partie normalisée)
  local final_tags=()
  for entry in "${sorted_tags[@]}"; do
    local real_tag="${entry#*|}"
    final_tags+=("$real_tag")
  done
  
  # Limiter le nombre de tags à considérer
  if [[ ${#final_tags[@]} -gt $limit ]]; then
    final_tags=("${final_tags[@]:0:$limit}")
  fi
  
  # Si une version actuelle est spécifiée, trouver la version juste avant
  if [[ -n "$current_version" ]]; then
    local previous_tag=""
    local found_current=false
    
    for tag in "${final_tags[@]}"; do
      if [[ "$tag" == "$current_version" ]]; then
        found_current=true
        continue
      fi
      
      if [[ "$found_current" == "true" ]]; then
        previous_tag="$tag"
        break
      fi
    done
    
    # Si la version actuelle n'a pas été trouvée, prendre la version précédente directement
    if [[ "$found_current" == "false" ]]; then
      for tag in "${final_tags[@]}"; do
        local comparison
        comparison=$(compare_versions "$current_version" "$tag")
        if [[ "$comparison" == "1" ]]; then
          previous_tag="$tag"
          break
        fi
      done
    fi
    
    echo "$previous_tag"
  else
    # Sinon, retourner la version la plus récente
    if [[ ${#final_tags[@]} -gt 0 ]]; then
      echo "${final_tags[0]}"
    else
      echo ""
    fi
  fi
}

function get_previous_version_from_releases() {
  local current_version="${CURRENT_VERSION}"
  local pattern="${VERSION_PATTERN}"
  local exclude_pre_releases="${EXCLUDE_PRE_RELEASES}"
  local exclude_drafts="${EXCLUDE_DRAFTS}"
  local flavor="${PRODUCT_FLAVOR}"
  
  # Si en mode offline, forcer l'utilisation des tags
  if [[ "${OFFLINE_MODE}" == "true" ]]; then
    debug "Mode offline activé, utilisation des tags git"
    echo $(get_previous_version_from_tags)
    return
  }
  
  # Échapper les caractères spéciaux dans flavor pour jq
  local escaped_flavor=""
  if [[ -n "$flavor" ]]; then
    escaped_flavor=$(echo "$flavor" | sed 's/\./\\\\./g' | sed 's/\-/\\\\-/g')
  fi
  
  # Récupérer les releases depuis l'API GitHub
  local releases_data
  releases_data=$(get_github_releases)
  
  # Vérifier si on doit fallback aux tags
  if [[ "$releases_data" == "FALLBACK_TO_TAGS" ]]; then
    debug "Fallback aux tags, échec API GitHub"
    echo $(get_previous_version_from_tags)
    return
  fi
  
  # S'assurer que la réponse est valide
  if ! echo "$releases_data" | jq -e . >/dev/null 2>&1; then
    warn "Erreur lors de la récupération des releases, fallback aux tags"
    echo $(get_previous_version_from_tags)
    return
  fi
  
  # Filtrer les releases avec jq
  local filter_query
  filter_query='[.[] | select(
    (.tag_name | test($pattern)) and
    ($exclude_pre == "false" or .prerelease == false) and
    ($exclude_drafts == "false" or .draft == false)'
  
  # Ajouter le filtre de saveur si spécifié
  if [[ -n "$flavor" ]]; then
    filter_query+=' and
    (.tag_name | test("[-_.]" + $flavor + "[-_.]|[-_.]" + $flavor + "$|^" + $flavor + "[-_.]"))'
  fi
  
  filter_query+=')] | sort_by(.published_at) | reverse | .[].tag_name'
  
  local filtered_releases
  filtered_releases=$(echo "$releases_data" | jq -r --arg pattern "$pattern" \
                                                --arg exclude_pre "$exclude_pre_releases" \
                                                --arg exclude_drafts "$exclude_drafts" \
                                                --arg flavor "$escaped_flavor" \
                                                "$filter_query")
  
  debug "Releases filtrées: $filtered_releases"
  
  # Convertir en tableau
  local sorted_releases
  IFS=$'\n' sorted_releases=($filtered_releases)
  unset IFS
  
  # Si une version actuelle est spécifiée, trouver la version juste avant
  if [[ -n "$current_version" ]]; then
    local previous_release=""
    local found_current=false
    
    for release in "${sorted_releases[@]}"; do
      if [[ "$release" == "$current_version" ]]; then
        found_current=true
        continue
      fi
      
      if [[ "$found_current" == "true" ]]; then
        previous_release="$release"
        break
      fi
    done
    
    # Si la version actuelle n'a pas été trouvée, prendre la version précédente directement
    if [[ "$found_current" == "false" ]]; then
      for release in "${sorted_releases[@]}"; do
        local comparison
        comparison=$(compare_versions "$current_version" "$release")
        if [[ "$comparison" == "1" ]]; then
          previous_release="$release"
          break
        fi
      done
    fi
    
    echo "$previous_release"
  else
    # Sinon, retourner la version la plus récente
    if [[ ${#sorted_releases[@]} -gt 0 ]]; then
      echo "${sorted_releases[0]}"
    else
      echo ""
    fi
  fi
}

# ==============================================================================
# FONCTIONS DE TESTS
# ==============================================================================

function run_semver_tests() {
  echo "Exécution des tests SemVer..."
  
  # Test de normalize_version
  local norm_result=$(normalize_version "v1.2.3-alpha.1+build.1")
  echo "Test normalize_version: $norm_result"
  
  # Test de normalize_prerelease pour alpha.1 vs alpha.10
  local pre1=$(normalize_prerelease "alpha.1")
  local pre2=$(normalize_prerelease "alpha.10")
  echo "Test normalize_prerelease: alpha.1 -> $pre1, alpha.10 -> $pre2"
  if [[ "$pre1" > "$pre2" ]]; then
    echo "❌ Échec: alpha.1 > alpha.10"
  else
    echo "✅ Succès: alpha.1 < alpha.10"
  fi
  
  # Tests compare_versions
  local tests=(
    "1.0.0 1.0.0 0"
    "1.0.0 1.0.1 -1"
    "1.0.1 1.0.0 1"
    "1.0.0 1.1.0 -1"
    "1.1.0 1.0.0 1"
    "1.0.0 2.0.0 -1"
    "2.0.0 1.0.0 1"
    "1.0.0 1.0.0-alpha 1"
    "1.0.0-alpha 1.0.0 -1"
    "1.0.0-alpha 1.0.0-alpha.1 -1"
    "1.0.0-alpha.1 1.0.0-alpha -1"
    "1.0.0-alpha.1 1.0.0-alpha.2 -1"
    "1.0.0-alpha.2 1.0.0-alpha.1 1"
    "1.0.0-alpha.10 1.0.0-alpha.2 1"
    "1.0.0-alpha.2 1.0.0-alpha.10 -1"
  )
  
  local passed=0
  local failed=0
  
  for test in "${tests[@]}"; do
    read -r v1 v2 expected <<< "$test"
    local result=$(compare_versions "$v1" "$v2")
    
    if [[ "$result" == "$expected" ]]; then
      echo "✅ $v1 vs $v2 = $result"
      passed=$((passed + 1))
    else
      echo "❌ $v1 vs $v2 = $result (attendu: $expected)"
      failed=$((failed + 1))
    fi
  done
  
  echo "Tests terminés: $passed réussis, $failed échoués"
  
  # Test is_pre_release
  local pre_release_test1=$(is_pre_release "1.0.0-alpha")
  local pre_release_test2=$(is_pre_release "1.0.0")
  
  if [[ "$pre_release_test1" == "true" && "$pre_release_test2" == "false" ]]; then
    echo "✅ Test is_pre_release: réussi"
    passed=$((passed + 1))
  else
    echo "❌ Test is_pre_release: échoué"
    failed=$((failed + 1))
  fi
  
  # Test de filtrage avec flavor
  PRODUCT_FLAVOR="premium"
  local flavor_test1=$(version_matches_flavor "v1.0.0-premium")
  local flavor_test2=$(version_matches_flavor "v1.0.0")
  
  if [[ "$flavor_test1" == "true" && "$flavor_test2" == "false" ]]; then
    echo "✅ Test version_matches_flavor: réussi"
    passed=$((passed + 1))
  else
    echo "❌ Test version_matches_flavor: échoué"
    failed=$((failed + 1))
  fi
  
  echo "Résumé des tests: $passed réussis, $failed échoués"
  
  # Nettoyage de la variable globale
  PRODUCT_FLAVOR=""
  
  # Si des tests ont échoué, sortir avec un code d'erreur
  if [[ $failed -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ==============================================================================
# FONCTION DE TRAITEMENT DES VERSIONS
# ==============================================================================

function process_and_output_version() {
  local previous_version="$1"
  
  # Extraire les composantes de la version
  read -r major minor patch prerelease buildmeta <<< "$(extract_semver_components "$previous_version")"
  
  # Définir les sorties
  set_output "previous-version" "${major}.${minor}.${patch}"
  set_output "previous-version-tag" "$previous_version"
  set_output "major" "$major"
  set_output "minor" "$minor"
  set_output "patch" "$patch"
  
  if [[ -n "$prerelease" ]]; then
    set_output "pre-release" "$prerelease"
  fi
  
  if [[ -n "$buildmeta" ]]; then
    set_output "build-metadata" "$buildmeta"
  fi
  
  # Informations supplémentaires
  if [[ "${OFFLINE_MODE}" != "true" && "${VERSION_SOURCE}" == "releases" ]]; then
    local release_date
    release_date=$(get_version_date "$previous_version" "${VERSION_SOURCE}")
    if [[ -n "$release_date" ]]; then
      set_output "release-date" "$release_date"
    fi
    
    local changelog_url
    changelog_url=$(get_changelog_url "$previous_version")
    if [[ -n "$changelog_url" ]]; then
      set_output "changelog-url" "$changelog_url"
    fi
    
    local release_id
    release_id=$(get_release_id "$previous_version")
    if [[ -n "$release_id" ]]; then
      set_output "release-id" "$release_id"
    fi
  elif [[ "${VERSION_SOURCE}" == "tags" || "${OFFLINE_MODE}" == "true" ]]; then
    # Pour les tags, on peut toujours obtenir la date et l'URL
    local release_date
    release_date=$(get_version_date "$previous_version" "tags")
    if [[ -n "$release_date" ]]; then
      set_output "release-date" "$release_date"
    fi
    
    local changelog_url
    changelog_url=$(get_changelog_url "$previous_version")
    if [[ -n "$changelog_url" ]]; then
      set_output "changelog-url" "$changelog_url"
    fi
  fi
  
  local commits_since
  commits_since=$(count_commits_since "$previous_version")
  if [[ -n "$commits_since" ]]; then
    set_output "commits-since" "$commits_since"
  fi
  
  # Déterminer si la version majeure a changé par rapport à la version actuelle
  if [[ -n "${CURRENT_VERSION}" ]]; then
    read -r current_major _ _ _ _ <<< "$(extract_semver_components "${CURRENT_VERSION}")"
    
    if [[ "$current_major" -ne "$major" ]]; then
      set_output "major-changed" "true"
    else
      set_output "major-changed" "false"
    fi
  fi
}

# ==============================================================================
# FONCTION PRINCIPALE
# ==============================================================================

function main() {
  # Si les tests sont demandés, les exécuter
  if [[ "${EXECUTE_TESTS}" == "true" ]]; then
    run_semver_tests
    exit $?
  }
  
  # Initialiser les variables d'environnement
  initialize_environment_variables
  
  # Valider les entrées
  validate_inputs
  
  # Vérifier les prérequis
  check_requirements
  
  # Initialiser les informations du dépôt
  initialize_repo_info
  
  log "Recherche de la version précédente depuis ${VERSION_SOURCE}..."
  
  # Récupérer la version précédente selon la source spécifiée
  local previous_version=""
  
  # Forcer l'utilisation des tags si en mode hors ligne
  if [[ "${OFFLINE_MODE}" == "true" ]]; then
    log "Mode hors ligne activé, utilisation des tags git"
    previous_version=$(get_previous_version_from_tags)
  else
    case "${VERSION_SOURCE}" in
      "tags")
        previous_version=$(get_previous_version_from_tags)
        ;;
      "releases")
        previous_version=$(get_previous_version_from_releases)
        ;;
      "package")
        # Non implémenté pour le moment - fallback aux tags
        warn "Source 'package' non implémentée. Utilisation des tags comme fallback."
        previous_version=$(get_previous_version_from_tags)
        ;;
    esac
  fi
  
  # Si aucune version n'a été trouvée, utiliser la version par défaut
  if [[ -z "$previous_version" ]]; then
    warn "Aucune version précédente trouvée. Utilisation de la version par défaut: ${FALLBACK_VERSION}"
    previous_version="${FALLBACK_VERSION}"
    set_output "has-previous" "false"
  else
    log "Version précédente trouvée: $previous_version"
    set_output "has-previous" "true"
  fi
  
  # Traiter et générer les sorties
  process_and_output_version "$previous_version"
  
  log "Extraction de la version précédente terminée avec succès."
  return 0
}

# Exécution de la fonction principale
main "$@"