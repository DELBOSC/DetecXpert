#!/usr/bin/env bash
# =========================================================================
# version-info.sh - Système de gestion de version pour CI/CD
# =========================================================================
# 
# Version améliorée après revue : séparation en modules,
# gestion d'erreurs robuste et traitement optimisé des cas limites
#
# =========================================================================

# Version du script
readonly VERSION_INFO_VERSION="2.1.0"

# Mode strict : arrête l'exécution à la première erreur,
# considère les variables non définies comme des erreurs,
# propage les erreurs dans les pipes
set -euo pipefail

# =========================================================================
# INITIALISATION
# =========================================================================

# Chemin du script et répertoire parent
readonly SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Initialisation des variables pour stocker la config
declare -A CONFIG=()
declare -A OUTPUT_VARS=()

# Codes de sortie
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_VERSION=2
readonly EXIT_JSON_PARSE_ERROR=3
readonly EXIT_INVALID_BUMP=4
readonly EXIT_DATE_ERROR=5
readonly EXIT_DEPENDENCY_MISSING=6
readonly EXIT_INVALID_PARAM=7
readonly EXIT_PERMISSION_ERROR=8

# Capture globale d'erreurs pour affichage détaillé
trap 'echo "❌ Erreur à la ligne $LINENO, commande: $BASH_COMMAND, code: $?" >&2; exit $EXIT_GENERAL_ERROR' ERR

# Capture les signaux pour cleanup propre si nécessaire
trap 'echo "⚠️ Script interrompu par l utilisateur" >&2; exit $EXIT_GENERAL_ERROR' INT TERM

# =========================================================================
# CHARGEMENT DES MODULES
# =========================================================================

# Détermine si nous sommes en mode modulaire ou monolithique
if [[ -d "$SCRIPT_DIR/lib" ]]; then
    # Mode modulaire : charge chaque module séparément
    # shellcheck source=lib/logging.sh
    source "$SCRIPT_DIR/lib/logging.sh"
    # shellcheck source=lib/utils.sh
    source "$SCRIPT_DIR/lib/utils.sh"
    # shellcheck source=lib/config.sh
    source "$SCRIPT_DIR/lib/config.sh"
    # shellcheck source=lib/semver.sh
    source "$SCRIPT_DIR/lib/semver.sh"
    # shellcheck source=lib/git.sh
    source "$SCRIPT_DIR/lib/git.sh"
    # shellcheck source=lib/version.sh
    source "$SCRIPT_DIR/lib/version.sh"
    # shellcheck source=lib/snapshot.sh
    source "$SCRIPT_DIR/lib/snapshot.sh"
    # shellcheck source=lib/output.sh
    source "$SCRIPT_DIR/lib/output.sh"
else
    # Mode monolithique : définitions intégrées (conserver le code ici)
    # [Contenu du script monolithique]
    
    # CONSTANTS
    # -------- 

    # Chemins par défaut
    readonly DEFAULT_GRADLE_PATH="./gradle.properties"
    readonly DEFAULT_VERSION_KT_PATH="./build-system/gradle/core/Versions.kt"
    readonly DEFAULT_VERSION_PREFIX="v"

    # Formats et patterns - Renforcés selon vos suggestions
    readonly REGEX_VERSION="^([0-9]+)\.([0-9]+)\.([0-9]+)(-[A-Za-z0-9\.\-]+)?(\+[A-Za-z0-9\.\-]+)?$"
    readonly REGEX_GRADLE_VERSION="^[[:space:]]*(?!#|\\/\\/)(version|VERSION_NAME|appVersion)[[:space:]]*=[[:space:]]*[\"']?([^\"']+)[\"']?"
    readonly REGEX_KOTLIN_VERSION="(?!\\s*\\/\\/)(val APP_VERSION|const val VERSION_NAME)[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"']"

    # Valeurs acceptées
    readonly VALID_SNAPSHOT_MODES="true false auto"
    readonly VALID_BUMP_TYPES="major minor patch prerelease"
    readonly VALID_OUTPUT_FORMATS="github dotenv json plain yaml xml"
    
    # Branches de production
    readonly DEFAULT_PRODUCTION_BRANCHES="main master release.* hotfix.*"

    # MODULE: logging.sh
    # -----------------
    
    # Constantes pour le logging
    readonly LOG_INFO="INFO"
    readonly LOG_WARN="WARN"
    readonly LOG_ERROR="ERROR"
    readonly LOG_DEBUG="DEBUG"
    
    # Couleurs et styles
    readonly COLOR_RESET="\033[0m"
    readonly COLOR_INFO="\033[94m"      # Bleu
    readonly COLOR_WARN="\033[93m"      # Jaune
    readonly COLOR_ERROR="\033[91m"     # Rouge
    readonly COLOR_DEBUG="\033[90m"     # Gris
    readonly COLOR_SUCCESS="\033[92m"   # Vert
    
    # Emojis pour logging (peut être désactivé avec NO_EMOJI=true)
    readonly EMOJI_INFO="ℹ️ "
    readonly EMOJI_WARN="⚠️ "
    readonly EMOJI_ERROR="❌ "
    readonly EMOJI_DEBUG="🔍 "
    readonly EMOJI_SUCCESS="✅ "
    
    # Configuration du logging
    USE_COLOR=true
    USE_EMOJI=true
    
    # Vérifie si la sortie erreur est un terminal dès l'initialisation pour optimiser
    if [[ ! -t 2 || "${NO_COLOR:-false}" == "true" ]]; then
        USE_COLOR=false
    fi
    
    # Désactive les emojis si demandé
    if [[ "${NO_EMOJI:-false}" == "true" ]]; then
        USE_EMOJI=false
    fi
    
    # Fonction de logging avec niveaux, timestamps, couleurs et emojis
    log() {
      local level="$1"
      local message="$2"
      local color prefix timestamp
      
      # Ne pas afficher les messages DEBUG si VERBOSE n'est pas activé
      if [[ "$level" == "$LOG_DEBUG" && "${VERBOSE:-false}" != "true" ]]; then
        return
      }
      
      # Déterminer la couleur et l'emoji selon le niveau
      case "$level" in
        "$LOG_INFO")  
            color="$COLOR_INFO"
            prefix="$([[ "$USE_EMOJI" == "true" ]] && echo "$EMOJI_INFO" || echo "[INFO] ")"
            ;;
        "$LOG_WARN")  
            color="$COLOR_WARN"
            prefix="$([[ "$USE_EMOJI" == "true" ]] && echo "$EMOJI_WARN" || echo "[WARN] ")"
            ;;
        "$LOG_ERROR") 
            color="$COLOR_ERROR"
            prefix="$([[ "$USE_EMOJI" == "true" ]] && echo "$EMOJI_ERROR" || echo "[ERROR] ")"
            ;;
        "$LOG_DEBUG") 
            color="$COLOR_DEBUG"
            prefix="$([[ "$USE_EMOJI" == "true" ]] && echo "$EMOJI_DEBUG" || echo "[DEBUG] ")"
            ;;
        *)            
            color="$COLOR_RESET"
            prefix="[LOG] "
            ;;
      esac
      
      # Générer le timestamp
      timestamp=$(date +"%Y-%m-%d %H:%M:%S")
      
      # Afficher le message formaté
      if [[ "$USE_COLOR" == "true" ]]; then
        # Terminal avec couleur
        printf "%b%s [%s] %s%b\n" "$color" "$prefix" "$timestamp" "$message" "$COLOR_RESET" >&2
      else
        # Sans couleur (redirection ou NO_COLOR activé)
        printf "%s[%s] %s\n" "$prefix" "$timestamp" "$message" >&2
      fi
    }
    
    # Raccourcis pour les différents niveaux de log
    log_info() { log "$LOG_INFO" "$1"; }
    log_warn() { log "$LOG_WARN" "$1"; }
    log_error() { log "$LOG_ERROR" "$1"; }
    log_debug() { log "$LOG_DEBUG" "$1"; }
    log_success() { 
        local message="$1"
        local prefix="$([[ "$USE_EMOJI" == "true" ]] && echo "$EMOJI_SUCCESS" || echo "[SUCCESS] ")"
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        
        if [[ "$USE_COLOR" == "true" ]]; then
            printf "%b%s [%s] %s%b\n" "$COLOR_SUCCESS" "$prefix" "$timestamp" "$message" "$COLOR_RESET" >&2
        else
            printf "%s[%s] %s\n" "$prefix" "$timestamp" "$message" >&2
        fi
    }

    # MODULE: utils.sh
    # ---------------
    
    # Vérifie si une commande est disponible
    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }
    
    # Version améliorée pour écrire les sorties au format GitHub Actions
    write_github_output() {
      local key="$1"
      local value="$2"
      
      if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        if [[ -f "$GITHUB_OUTPUT" && -w "$GITHUB_OUTPUT" ]]; then
          # Multi-ligne : utiliser la syntaxe de délimiteur
          if [[ "$value" == *$'\n'* ]]; then
            local delimiter="EOF-$(openssl rand -hex 8)"
            {
              echo "$key<<$delimiter"
              echo "$value"
              echo "$delimiter"
            } >> "$GITHUB_OUTPUT"
          else
            # Valeur simple
            printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
          fi
        else
          log_warn "Impossible d'écrire dans GITHUB_OUTPUT, utilisation de la sortie standard"
          echo "::set-output name=$key::$value"
        fi
      fi
    }
    
    # Accumule les sorties pour génération JSON/YAML en une seule fois
    declare -A OUTPUT_ACCUMULATOR=()
    
    store_output() {
      local key="$1"
      local value="$2"
      
      OUTPUT_ACCUMULATOR["$key"]="$value"
      OUTPUT_VARS["$key"]="$value"
    }
    
    # Écrit les sorties selon le format demandé
    write_output() {
      local key="$1"
      local value="$2"
      
      # Stocke dans les deux tableaux
      store_output "$key" "$value"
      
      # Écrit immédiatement pour le format GitHub, dotenv et plain
      # (JSON/YAML/XML sont générés en une seule fois à la fin)
      case "${OUTPUT_FORMAT:-github}" in
        github)
          write_github_output "$key" "$value"
          ;;
        dotenv)
          printf '%s=%s\n' "$key" "$value" >> "${OUTPUT_FILE:-.env}"
          ;;
        plain)
          printf '%s=%s\n' "$key" "$value" >> "${OUTPUT_FILE:-version-info.txt}"
          ;;
      esac
    }
    
    # Génère tous les formats composites en une seule fois
    generate_output_file() {
      local format="${OUTPUT_FORMAT:-github}"
      local file="${OUTPUT_FILE:-}"
      
      case "$format" in
        json)
          # Génération JSON propre en une fois
          if [[ -n "$file" ]]; then
            {
              echo "{"
              local i=0
              local total=${#OUTPUT_ACCUMULATOR[@]}
              
              for key in "${!OUTPUT_ACCUMULATOR[@]}"; do
                ((i++))
                local value="${OUTPUT_ACCUMULATOR["$key"]}"
                # Échappe les caractères spéciaux JSON
                value="${value//\\/\\\\}"  # Backslash
                value="${value//\"/\\\"}"  # Guillemets
                value="${value//	/\\t}"  # Tab
                value="${value//\r/\\r}"   # CR
                value="${value//\n/\\n}"   # LF
                
                if [[ $i -eq $total ]]; then
                  # Dernière entrée sans virgule
                  printf '  "%s": "%s"\n' "$key" "$value"
                else
                  printf '  "%s": "%s",\n' "$key" "$value"
                fi
              done
              
              echo "}"
            } > "$file"
          fi
          ;;
        yaml)
          # Génération YAML propre
          if [[ -n "$file" ]]; then
            {
              for key in "${!OUTPUT_ACCUMULATOR[@]}"; do
                value="${OUTPUT_ACCUMULATOR["$key"]}"
                # Multi-lignes YAML avec | si nécessaire
                if [[ "$value" == *$'\n'* ]]; then
                  printf '%s: |\n' "$key"
                  printf '  %s\n' "${value//$'\n'/$'\n'  }"
                else
                  printf '%s: "%s"\n' "$key" "$value"
                fi
              done
            } > "$file"
          fi
          ;;
        xml)
          # Génération XML
          if [[ -n "$file" ]]; then
            {
              echo '<?xml version="1.0" encoding="UTF-8"?>'
              echo '<version-info>'
              
              for key in "${!OUTPUT_ACCUMULATOR[@]}"; do
                value="${OUTPUT_ACCUMULATOR["$key"]}"
                # Échappe les caractères XML
                value="${value//&/&amp;}"
                value="${value//</&lt;}"
                value="${value//>/&gt;}"
                value="${value//\"/&quot;}"
                value="${value//\'/&apos;}"
                
                printf '  <%s>%s</%s>\n' "$key" "$value" "$key"
              done
              
              echo '</version-info>'
            } > "$file"
          fi
          ;;
      esac
    }

    # MODULE: semver.sh
    # ----------------
    
    # Valide le format d'une version SemVer
    validate_semantic_version() {
      local version="$1"
      local detailed="${2:-false}"
      
      if [[ ! "$version" =~ $REGEX_VERSION ]]; then
        if [[ "$detailed" == "true" ]]; then
          log_error "Format de version invalide: $version"
          log_info "Les versions doivent respecter le format SemVer: X.Y.Z[-PRERELEASE][+BUILD]"
          log_info "Exemples: 1.2.3, 1.0.0-alpha, 2.3.0-beta.1, 1.0.0+20130313144700"
        else
          log_error "Version invalide: $version"
        fi
        return 1
      fi
      
      return 0
    }
    
    # Extrait les composants d'une version SemVer
    parse_version_components() {
      local version="$1"
      local -n ref_components="$2"
      
      # Si la version ne respecte pas SemVer, retourne une erreur
      if ! validate_semantic_version "$version"; then
        return 1
      fi
      
      # Extrait les composants à l'aide de regex
      if [[ "$version" =~ $REGEX_VERSION ]]; then
        ref_components["major"]="${BASH_REMATCH[1]}"
        ref_components["minor"]="${BASH_REMATCH[2]}"
        ref_components["patch"]="${BASH_REMATCH[3]}"
        ref_components["prerelease"]="${BASH_REMATCH[4]:-}"
        ref_components["buildmeta"]="${BASH_REMATCH[5]:-}"
        
        # Nettoie le préfixe de prérelease et buildmeta
        ref_components["prerelease"]=${ref_components["prerelease"]#-}
        ref_components["buildmeta"]=${ref_components["buildmeta"]#+}
        
        log_debug "Composants analysés: major=${ref_components["major"]}, minor=${ref_components["minor"]}, patch=${ref_components["patch"]}, prerelease=${ref_components["prerelease"]}, buildmeta=${ref_components["buildmeta"]}"
        return 0
      fi
      
      return 1
    }
    
    # Avance une version prérelease (alpha → alpha.1 → alpha.2)
    # Gère aussi les préfixes complexes (alpha.1.beta → alpha.1.beta.1)
    increment_prerelease() {
      local prerelease="$1"
      
      if [[ -z "$prerelease" ]]; then
        echo "alpha.1"
        return
      fi
      
      # Si se termine par un nombre, incrémente ce nombre
      if [[ "$prerelease" =~ (.*)\.([0-9]+)$ ]]; then
        local prefix="${BASH_REMATCH[1]}"
        local number="${BASH_REMATCH[2]}"
        echo "${prefix}.$(( number + 1 ))"
      else
        # Sinon ajoute .1
        echo "${prerelease}.1"
      fi
    }
    
    # Incrémente une version selon les règles SemVer
    bump_version() {
      local version="$1"
      local bump_type="$2"
      local pre_release_id="${3:-}"
      local -A components=()
      
      # Parse les composants de la version
      if ! parse_version_components "$version" components; then
        return 1
      fi
      
      # Sauvegarde la prérelease et buildmeta pour les restaurer après le bump
      local prerelease="${components["prerelease"]}"
      local buildmeta="${components["buildmeta"]}"
      local snapshot=false
      
      # Si la prérelease contient SNAPSHOT, le marquer pour le réappliquer plus tard
      if [[ "$prerelease" == *"SNAPSHOT"* ]]; then
        snapshot=true
        prerelease=${prerelease//SNAPSHOT/}
        prerelease=${prerelease//-/}
        [[ -z "$prerelease" ]] && prerelease=""
      fi
      
      # Incrémente selon le type
      case "$bump_type" in
        major)
          components["major"]=$((components["major"] + 1))
          components["minor"]=0
          components["patch"]=0
          # Les pré-releases et build metadata sont supprimés lors d'un bump major
          prerelease=""
          ;;
        minor)
          components["minor"]=$((components["minor"] + 1))
          components["patch"]=0
          # Les pré-releases sont supprimées lors d'un bump minor
          prerelease=""
          ;;
        patch)
          components["patch"]=$((components["patch"] + 1))
          # Les pré-releases sont supprimées lors d'un bump patch
          prerelease=""
          ;;
        prerelease)
          # Bump de prérelease - conserve major.minor.patch et incrémente/crée prérelease
          if [[ -z "$pre_release_id" ]]; then
            # Incrémente ou initialise la prérelease existante
            prerelease=$(increment_prerelease "$prerelease")
          else
            # Utilise l'identifiant fourni
            if [[ "$prerelease" == "$pre_release_id"* ]]; then
              # Même préfixe -> incrémente
              prerelease=$(increment_prerelease "$prerelease")
            else
              # Nouveau préfixe
              prerelease="$pre_release_id.1"
            fi
          fi
          ;;
        *)
          log_error "Type de bump non reconnu: $bump_type"
          log_info "Types de bump valides: major, minor, patch, prerelease"
          return 1
          ;;
      esac
      
      # Reconstruit la version
      local bumped_version="${components["major"]}.${components["minor"]}.${components["patch"]}"
      
      # Réapplique SNAPSHOT si nécessaire
      if [[ "$snapshot" == "true" ]]; then
        if [[ -n "$prerelease" ]]; then
          bumped_version+="-${prerelease}-SNAPSHOT"
        else
          bumped_version+="-SNAPSHOT"
        fi
      elif [[ -n "$prerelease" ]]; then
        bumped_version+="-$prerelease"
      fi
      
      # Réapplique buildmeta si présent
      [[ -n "$buildmeta" ]] && bumped_version+="+$buildmeta"
      
      log_info "Version après bump ($bump_type): $bumped_version"
      echo "$bumped_version"
    }
    
    # Calcule le code de version numérique
    calculate_version_code() {
      local major="$1" minor="$2" patch="$3"
      # Formule standard, mais en s'assurant d'interpréter en base 10
      echo $((10#$major*10000 + 10#$minor*100 + 10#$patch))
    }

    # MODULE: git.sh
    # -------------
    
    # Obtient la branche git actuelle
    get_current_branch() {
      local branch=""
      
      # 1. Essaie d'abord les variables d'environnement GitHub Actions
      if [[ -n "${GITHUB_HEAD_REF:-}" ]]; then
        branch="$GITHUB_HEAD_REF"
      elif [[ -n "${GITHUB_REF:-}" && "$GITHUB_REF" == refs/heads/* ]]; then
        branch="${GITHUB_REF#refs/heads/}"
      # 2. GitLab CI
      elif [[ -n "${CI_COMMIT_REF_NAME:-}" ]]; then
        branch="$CI_COMMIT_REF_NAME"
      # 3. Jenkins
      elif [[ -n "${GIT_BRANCH:-}" ]]; then
        branch="${GIT_BRANCH#*/}"
      # 4. Fallback sur git
      else
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
      fi
      
      log_debug "Branche détectée: ${branch:-<inconnue>}"
      echo "$branch"
    }
    
    # Vérifie si la branche actuelle est une branche de production
    is_production_branch() {
      local branch="$1"
      local prod_branches="${PRODUCTION_BRANCHES:-$DEFAULT_PRODUCTION_BRANCHES}"
      
      [[ -z "$branch" ]] && return 1
      
      for pattern in $prod_branches; do
        if [[ "$branch" =~ ^$pattern$ ]]; then
          log_debug "Branche '$branch' reconnue comme branche de production (pattern: $pattern)"
          return 0
        fi
      done
      
      log_debug "Branche '$branch' non reconnue comme branche de production"
      return 1
    }
    
    # Vérifie si le commit actuel est taggé
    is_tagged_commit() {
      # Plus robuste: vérifie d'abord si les tags existent, puis s'il y a un match
      if [[ "$(git tag -l 2>/dev/null | wc -l)" -eq 0 ]]; then
        log_debug "Aucun tag trouvé dans le dépôt"
        return 1
      fi
    
      if git describe --exact-match --tags HEAD >/dev/null 2>&1; then
        local tag
        tag=$(git describe --exact-match --tags HEAD 2>/dev/null)
        log_debug "Commit actuel est taggé avec: $tag"
        return 0
      fi
      
      log_debug "Commit actuel n'est pas taggé"
      return 1
    }
    
    # Obtient le hash du commit git actuel
    get_git_commit() {
      local hash
      
      # Essaie d'abord les variables CI
      if [[ -n "${GITHUB_SHA:-}" ]]; then
        hash="$GITHUB_SHA"
      elif [[ -n "${CI_COMMIT_SHA:-}" ]]; then
        hash="$CI_COMMIT_SHA"
      # Jenkins
      elif [[ -n "${GIT_COMMIT:-}" ]]; then
        hash="$GIT_COMMIT"
      else
        hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
      fi
      
      log_debug "Hash du commit git: $hash"
      echo "$hash"
    }

    # MODULE: version.sh
    # -----------------
    
    # Priorités d'extraction (1 = plus haute priorité)
    readonly VERSION_PRIORITY_GRADLE_VERSION=1
    readonly VERSION_PRIORITY_GRADLE_VERSION_NAME=2
    readonly VERSION_PRIORITY_GRADLE_APP_VERSION=3
    readonly VERSION_PRIORITY_KOTLIN_APP_VERSION=4
    readonly VERSION_PRIORITY_KOTLIN_VERSION_NAME=5
    
    # Extrait la version de gradle.properties avec priorité
    extract_from_gradle_properties() {
      local file="$1"
      local best_version=""
      local best_priority=999
      
      if [[ -f "$file" ]]; then
        log_debug "Recherche de version dans $file"
        
        # Cherche toutes les correspondances possibles
        while IFS= read -r line; do
          if [[ "$line" =~ $REGEX_GRADLE_VERSION ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Détermine la priorité
            local priority
            case "$key" in
              version)     priority=$VERSION_PRIORITY_GRADLE_VERSION ;;
              VERSION_NAME) priority=$VERSION_PRIORITY_GRADLE_VERSION_NAME ;;
              appVersion)  priority=$VERSION_PRIORITY_GRADLE_APP_VERSION ;;
              *)           priority=999 ;;
            esac
            
            # Conserve la version de plus haute priorité
            if [[ $priority -lt $best_priority ]]; then
              best_version="$value"
              best_priority=$priority
              log_debug "Trouvé $key=$value (priorité $priority)"
            fi
          fi
        done < "$file"
        
        if [[ -n "$best_version" ]]; then
          log_debug "Version extraite de gradle.properties: $best_version (priorité $best_priority)"
        else
          log_debug "Aucune version trouvée dans gradle.properties"
        fi
      else
        log_debug "Fichier gradle.properties non trouvé: $file"
      fi
      
      echo "$best_version"
    }
    
    # Extrait la version de Versions.kt avec priorité
    extract_from_versions_kt() {
      local file="$1"
      local best_version=""
      local best_priority=999
      
      if [[ -f "$file" ]]; then
        log_debug "Recherche de version dans $file"
        
        while IFS= read -r line; do
          if [[ "$line" =~ $REGEX_KOTLIN_VERSION ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Détermine la priorité
            local priority
            case "$key" in
              "val APP_VERSION")       priority=$VERSION_PRIORITY_KOTLIN_APP_VERSION ;;
              "const val VERSION_NAME") priority=$VERSION_PRIORITY_KOTLIN_VERSION_NAME ;;
              *)                        priority=999 ;;
            esac
            
            # Conserve la version de plus haute priorité
            if [[ $priority -lt $best_priority ]]; then
              best_version="$value"
              best_priority=$priority
              log_debug "Trouvé $key=$value (priorité $priority)"
            fi
          fi
        done < "$file"
        
        if [[ -n "$best_version" ]]; then
          log_debug "Version extraite de Versions.kt: $best_version (priorité $best_priority)"
        else
          log_debug "Aucune version trouvée dans Versions.kt"
        fi
      else
        log_debug "Fichier Versions.kt non trouvé: $file"
      fi
      
      echo "$best_version"
    }
    
    # Fonction centrale pour obtenir la version depuis toutes les sources possibles
    get_current_version() {
      local gradle_properties_path="$1"
      local version_file_path="$2"
      local custom_version="$3"
      local version=""
      
      if [[ -n "$custom_version" ]]; then
        log_info "Utilisation de la version personnalisée: $custom_version"
        version="$custom_version"
      else
        # Essaie d'abord gradle.properties puis Versions.kt
        if [[ -f "$gradle_properties_path" ]]; then
          version=$(extract_from_gradle_properties "$gradle_properties_path")
          [[ -n "$version" ]] && log_info "Version extraite de gradle.properties: $version"
        fi
        
        if [[ -z "$version" && -f "$version_file_path" ]]; then
          version=$(extract_from_versions_kt "$version_file_path")
          [[ -n "$version" ]] && log_info "Version extraite de Versions.kt: $version"
        fi
        
        if [[ -z "$version" ]]; then
          log_error "Impossible d'extraire la version des fichiers spécifiés"
          return 1
        fi
      fi
      
      # Nettoie la version
      version=${version//[\"\' ]/}
      echo "$version"
    }

    # MODULE: snapshot.sh
    # -----------------
    
    # Détermine si la version devrait être un snapshot
    # Factorisé en fonction dédiée comme suggéré
    determine_snapshot_auto() {
      local version="$1"
      local result="false"
      
      # Mode auto suit la logique de détection
      if [[ "$version" == *"-SNAPSHOT"* ]]; then
        # Déjà marqué comme snapshot
        log_debug "Mode auto: version contient déjà -SNAPSHOT"
        result="true"
      else
        # Vérifie si c'est une branche de production
        local branch
        branch=$(get_current_branch)
        
        if ! is_production_branch "$branch"; then
          # Branche non-production => snapshot
          log_debug "Mode auto: branche '$branch' non-production => snapshot"
          result="true"
        elif ! is_tagged_commit; then
          # Commit non taggé => snapshot
          log_debug "Mode auto: commit non taggé => snapshot"
          result="true"
        else
          # Branche de production + commit taggé => release
          log_debug "Mode auto: branche production + commit taggé => release"
          result="false"
        fi
      fi
      
      echo "$result"
    }
    
    # Fonction principale de détermination du mode snapshot
    determine_snapshot_mode() {
      local version="$1"
      local mode="$2"
      
      log_debug "Détermination du mode snapshot: version=$version, mode=$mode"
      
      case "$mode" in
        true)
          log_debug "Mode snapshot forcé à 'true'"
          echo "true"
          ;;
        false)
          log_debug "Mode snapshot forcé à 'false'"
          echo "false"
          ;;
        auto)
          determine_snapshot_auto "$version"
          ;;
        *)
          log_warn "Mode snapshot non reconnu: $mode. Utilisation de 'auto'"
          determine_snapshot_auto "$version"
          ;;
      esac
    }

    # MODULE: config.sh
    # ---------------
    
    # Vérifie si les paramètres fournis sont valides
    validate_input_params() {
      local snapshot_mode="${1:-auto}"
      local bump="${2:-}"
      local output_format="${3:-github}"
      local pre_release_id="${4:-}"
      
      log_debug "Validation des paramètres: snapshot_mode=$snapshot_mode, bump=$bump, output_format=$output_format, pre_release_id=$pre_release_id"
      
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
          log_error "Mode snapshot non valide: $snapshot_mode"
          log_info "Valeurs acceptées: $VALID_SNAPSHOT_MODES"
          return 1
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
          log_error "Type de bump non valide: $bump"
          log_info "Valeurs acceptées: $VALID_BUMP_TYPES"
          return 1
        fi
      fi
      
      # Validation du format de sortie
      if [[ -n "$output_format" ]]; then
        local valid_format=false
        for format in $VALID_OUTPUT_FORMATS; do
          if [[ "$output_format" == "$format" ]]; then
            valid_format=true
            break
          fi
        done
        
        if [[ "$valid_format" != "true" ]]; then
          log_error "Format de sortie non valide: $output_format"
          log_info "Valeurs acceptées: $VALID_OUTPUT_FORMATS"
          return 1
        fi
      fi
      
      return 0
    }
    
    # Extrait les valeurs JSON en utilisant jq
    parse_json_with_jq() {
      local json="$1"
      local -n ref_config="$2"
      
      log_debug "Analyse JSON avec jq"
      
      # Vérifie si le JSON est valide
      if ! jq empty 2>/dev/null <<<"$json"; then
        log_error "JSON invalide"
        return 1
      fi
      
      # Détecte si le JSON est complexe
      local is_complex
      is_complex=$(jq 'any(values|type=="object" or type=="array")' <<<"$json" 2>/dev/null || echo "false")
      [[ "$is_complex" == "true" ]] && log_info "JSON complexe détecté, utilisation de jq"
      
      # Extraction avec jq
      ref_config["gradle_properties_path"]=$(jq -r '.gradlePropertiesPath // .["gradle-properties-path"] // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["version_file_path"]=$(jq -r '.versionFilePath // .["version-file-path"] // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["custom_version"]=$(jq -r '.customVersion // .["custom-version"] // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["snapshot_mode"]=$(jq -r '.snapshot // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["version_prefix"]=$(jq -r '.versionPrefix // .["version-prefix"] // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["bump"]=$(jq -r '.bump // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["production_branches"]=$(jq -r '.productionBranches // .["production-branches"] // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["output_format"]=$(jq -r '.outputFormat // .["output-format"] // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["output_file"]=$(jq -r '.outputFile // .["output-file"] // empty' <<<"$json" 2>/dev/null || echo "")
      ref_config["pre_release_id"]=$(jq -r '.preReleaseId // .["pre-release-id"] // empty' <<<"$json" 2>/dev/null || echo "")
      
      return 0
    }
    
    # Parse la configuration JSON
    parse_config_json() {
      local json="$1"
      local -n ref_config="$2"
      
      log_info "Utilisation de la configuration JSON"
      
      # Si le JSON est potentiellement complexe, jq est requis
      if [[ "$json" =~ [{\[].*[{\[] || "$json" =~ [:,][[:space:]]*[\[\{] ]]; then
        if ! command_exists jq; then
          log_error "JSON complexe détecté mais jq n'est pas disponible"
          log_info "Installez jq pour traiter des JSON complexes: apt install jq / brew install jq"
          return 1
        fi
        
        parse_json_with_jq "$json" ref_config
        return $?
      fi
      
      # JSON simple - continuer même sans jq
      if ! command_exists jq; then
        log_warn "jq n'est pas disponible, utilisation d'un parsing JSON simplifié (limité aux clés simples)"
      else
        parse_json_with_jq "$json" ref_config
        return $?
      fi
      
      # Fallback très simple pour JSON basique
      # Note: ne gère pas les valeurs contenant virgules/espaces - devrait suffire pour config simple
      log_warn "Utilisation du parser JSON simplifié - limité aux formats simples"
      
      # Extraction avec méthode simple
      if [[ "$json" =~ \"gradlePropertiesPath\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["gradle_properties_path"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"gradle-properties-path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["gradle_properties_path"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"versionFilePath\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["version_file_path"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"version-file-path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["version_file_path"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"customVersion\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["custom_version"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"custom-version\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["custom_version"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"snapshot\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["snapshot_mode"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"snapshot\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
        ref_config["snapshot_mode"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"versionPrefix\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["version_prefix"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"version-prefix\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["version_prefix"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"bump\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["bump"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"productionBranches\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["production_branches"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"production-branches\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["production_branches"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"outputFormat\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["output_format"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"output-format\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["output_format"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"outputFile\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["output_file"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"output-file\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["output_file"]="${BASH_REMATCH[1]}"
      fi
      
      if [[ "$json" =~ \"preReleaseId\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["pre_release_id"]="${BASH_REMATCH[1]}"
      elif [[ "$json" =~ \"pre-release-id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        ref_config["pre_release_id"]="${BASH_REMATCH[1]}"
      fi
      
      return 0
    }
    
    # Charge la configuration depuis un fichier JSON
    load_config_file() {
      local file="$1"
      local -n ref_config="$2"
      
      if [[ ! -f "$file" ]]; then
        log_error "Fichier de configuration non trouvé: $file"
        return 1
      fi
      
      log_info "Chargement de la configuration depuis $file"
      local json
      json=$(cat "$file")
      
      parse_config_json "$json" ref_config
      return $?
    }

    # Obtient la date de build au format ISO 8601
    get_build_date() {
      local date_command date_format date_str
      date_format="%Y-%m-%dT%H:%M:%SZ"
      
      # Essaie d'abord la commande 'date'
      if date -u +"$date_format" >/dev/null 2>&1; then
        date_command="date -u"
      # Fallback sur 'gdate' (GNU date sur macOS via coreutils)
      elif command_exists gdate && gdate -u +"$date_format" >/dev/null 2>&1; then
        date_command="gdate -u"
      # Dernier recours: date sans -u (moins précis)
      else
        date_command="date"
      fi
      
      date_str=$($date_command +"$date_format" 2>/dev/null || echo "")
      
      if [[ -z "$date_str" ]]; then
        log_error "Impossible de générer la date ISO"
        return 1
      fi
      
      log_debug "Date de build générée: $date_str"
      echo "$date_str"
    }
    
    # Traite le mode dry-run
    handle_dry_run() {
      log_info "Mode dry-run activé, les valeurs suivantes sont factices"
      
      # Date et commit pour ajouter un peu de réalisme
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
      
      # Finalisation des formats composites
      generate_output_file
      
      log_success "Exécution dry-run terminée avec succès"
      exit $EXIT_SUCCESS
    }
    
    # Affiche l'aide
    show_help() {
      if [[ "${1:-}" == "verbose" ]]; then
        cat <<EOF
Version Info v${VERSION_INFO_VERSION} - Système avancé de gestion de version

UTILISATION:
  ./version-info.sh [options]

OPTIONS:
  --help                Affiche cette aide
  --verbose-help        Affiche l'aide détaillée
  --dry-run             Mode simulation, ne modifie rien (équivalent à DRY_RUN=true)
  --verbose             Mode verbeux (équivalent à VERBOSE=true)
  --config FILE         Charge la configuration depuis un fichier JSON
  --output-format FMT   Format de sortie (github, dotenv, json, plain, yaml, xml)
  --output-file FILE    Fichier de sortie (par défaut dépend du format)
  --pre-release ID      Identifiant pour les versions pré-release
  --no-emoji            Désactive les emojis dans les logs
  --no-color            Désactive les couleurs dans les logs

VARIABLES D'ENVIRONNEMENT:
  GRADLE_PROPERTIES_PATH   Chemin vers gradle.properties (défaut: $DEFAULT_GRADLE_PATH)
  VERSION_FILE_PATH        Chemin vers Versions.kt (défaut: $DEFAULT_VERSION_KT_PATH)
  CUSTOM_VERSION           Version personnalisée (optionnel)
  SNAPSHOT_MODE            Mode snapshot 'true', 'false', ou 'auto' (défaut: auto)
  VERSION_PREFIX           Préfixe de version (défaut: $DEFAULT_VERSION_PREFIX)
  DRY_RUN                  Mode simulation 'true' ou 'false' (défaut: false)
  BUMP                     Incrémenter 'major', 'minor', 'patch', 'prerelease' (optionnel)
  PRE_RELEASE_ID           Identifiant pour les bumps prerelease (optionnel)
  CONFIG_JSON              Configuration JSON (optionnel)
  CONFIG_FILE              Chemin vers un fichier de configuration JSON (optionnel)
  PRODUCTION_BRANCHES      Branches considérées en production (défaut: "$DEFAULT_PRODUCTION_BRANCHES")
  OUTPUT_FORMAT            Format de sortie (github, dotenv, json, plain, yaml, xml) (défaut: github)
  OUTPUT_FILE              Fichier de sortie (dépend du format)
  VERBOSE                  Mode verbeux 'true' ou 'false' (défaut: false)
  NO_COLOR                 Désactive la coloration des logs 'true' ou 'false' (défaut: false)
  NO_EMOJI                 Désactive les emojis dans les logs 'true' ou 'false' (défaut: false)

EXEMPLES D'UTILISATION:
  # Utilisation basique
  ./version-info.sh
  
  # Incrémenter la version mineure
  BUMP=minor ./version-info.sh
  
  # Version personnalisée en mode non-snapshot
  CUSTOM_VERSION=1.2.3 SNAPSHOT_MODE=false ./version-info.sh
  
  # Définir les branches de production à considérer
  PRODUCTION_BRANCHES="main release/*" ./version-info.sh
  
  # Créer une version pré-release
  BUMP=prerelease PRE_RELEASE_ID=beta ./version-info.sh
  
  # Obtenir une sortie JSON
  OUTPUT_FORMAT=json OUTPUT_FILE=version.json ./version-info.sh
  
  # Charger la configuration depuis un fichier
  CONFIG_FILE=version-config.json ./version-info.sh

SORTIES:
  version                Version complète avec préfixe (ex: v1.2.3-SNAPSHOT)
  version_name           Version sans préfixe (ex: 1.2.3-SNAPSHOT)
  version_code           Représentation numérique (ex: 10203)
  major                  Composant majeur (ex: 1)
  minor                  Composant mineur (ex: 2)
  patch                  Composant patch (ex: 3)
  is_snapshot            Indicateur de snapshot (true/false)
  is_release             Indicateur de release (true/false)
  build_date             Date de build au format ISO 8601
  git_commit             Hash du commit Git actuel

EOF
      else
        cat <<EOF
Version Info v${VERSION_INFO_VERSION} - Système de gestion de version pour CI/CD

UTILISATION:
  ./version-info.sh [options]

OPTIONS principales:
  --help                Affiche cette aide
  --verbose-help        Affiche l'aide détaillée avec tous les paramètres
  --dry-run             Mode simulation, ne modifie rien
  --config FILE         Charge la configuration depuis un fichier JSON
  --output-format FMT   Format de sortie (github, dotenv, json, plain, yaml, xml)
  --output-file FILE    Fichier de sortie
  --pre-release ID      Identifiant pour les versions pré-release

Utilisez --verbose-help pour voir toutes les options et variables d'environnement.

EXEMPLES COURANTS:
  # Utilisation basique
  ./version-info.sh
  
  # Incrémenter la version
  BUMP=minor ./version-info.sh
  
  # Version personnalisée
  CUSTOM_VERSION=1.2.3 ./version-info.sh
  
  # Sortie JSON
  ./version-info.sh --output-format json --output-file version.json
EOF
      fi
    }
fi

# =========================================================================
# FONCTION PRINCIPALE
# =========================================================================

main() {
  # Initialisation du tableau associatif pour les sorties
  declare -A OUTPUT_VARS=(
    ["version"]=""
    ["version_name"]=""
    ["version_code"]=""
    ["major"]=""
    ["minor"]=""
    ["patch"]=""
    ["is_snapshot"]=""
    ["is_release"]=""
    ["build_date"]=""
    ["git_commit"]=""
  )
  
  log_debug "Version Info v${VERSION_INFO_VERSION} - Démarrage"
  
  # Traitement des paramètres de ligne de commande
  local output_format="github"
  local output_file=""
  local pre_release_id=""
  
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      --help)
        show_help
        exit $EXIT_SUCCESS
        ;;
      --verbose-help)
        show_help "verbose"
        exit $EXIT_SUCCESS
        ;;
      --dry-run)
        export DRY_RUN=true
        shift
        ;;
      --verbose)
        export VERBOSE=true
        shift
        ;;
      --no-emoji)
        export NO_EMOJI=true
        shift
        ;;
      --no-color)
        export NO_COLOR=true
        shift
        ;;
      --config)
        export CONFIG_FILE="$2"
        shift 2
        ;;
      --output-format)
        output_format="$2"
        shift 2
        ;;
      --output-file)
        output_file="$2"
        shift 2
        ;;
      --pre-release)
        pre_release_id="$2"
        shift 2
        ;;
      *)
        log_error "Option non reconnue: $key"
        log_info "Utilisez --help pour afficher l'aide"
        exit $EXIT_INVALID_PARAM
        ;;
    esac
  done
  
  # Priorité pour les options de ligne de commande
  export OUTPUT_FORMAT="${OUTPUT_FORMAT:-$output_format}"
  export OUTPUT_FILE="${OUTPUT_FILE:-$output_file}"
  export PRE_RELEASE_ID="${PRE_RELEASE_ID:-$pre_release_id}"
  
  # Configuration par défaut
  local gradle_properties_path="${GRADLE_PROPERTIES_PATH:-$DEFAULT_GRADLE_PATH}"
  local version_file_path="${VERSION_FILE_PATH:-$DEFAULT_VERSION_KT_PATH}"
  local custom_version="${CUSTOM_VERSION:-}"
  local snapshot_mode="${SNAPSHOT_MODE:-auto}"
  local version_prefix="${VERSION_PREFIX:-$DEFAULT_VERSION_PREFIX}"
  local bump="${BUMP:-}"
  local production_branches="${PRODUCTION_BRANCHES:-$DEFAULT_PRODUCTION_BRANCHES}"
  local pre_release_id="${PRE_RELEASE_ID:-}"
  
  # Vérifie les dépendances requises
  if ! command_exists git; then
    log_error "Git est requis mais n'est pas installé"
    exit $EXIT_DEPENDENCY_MISSING
  fi
  
  # Mode dry-run
  [[ "${DRY_RUN:-false}" == "true" ]] && handle_dry_run
  
  # Traite la configuration JSON (via variable ou fichier)
  declare -A config=()
  if [[ -n "${CONFIG_JSON:-}" ]]; then
    if ! parse_config_json "$CONFIG_JSON" config; then
      exit $EXIT_JSON_PARSE_ERROR
    fi
  elif [[ -n "${CONFIG_FILE:-}" ]]; then
    if ! load_config_file "$CONFIG_FILE" config; then
      exit $EXIT_JSON_PARSE_ERROR
    fi
  fi
  
  # Mise à jour de la configuration avec les valeurs JSON si présentes
  [[ -n "${config[gradle_properties_path]:-}" ]] && gradle_properties_path="${config[gradle_properties_path]}"
  [[ -n "${config[version_file_path]:-}" ]] && version_file_path="${config[version_file_path]}"
  [[ -n "${config[custom_version]:-}" ]] && custom_version="${config[custom_version]}"
  [[ -n "${config[snapshot_mode]:-}" ]] && snapshot_mode="${config[snapshot_mode]}"
  [[ -n "${config[version_prefix]:-}" ]] && version_prefix="${config[version_prefix]}"
  [[ -n "${config[bump]:-}" ]] && bump="${config[bump]}"
  [[ -n "${config[production_branches]:-}" ]] && production_branches="${config[production_branches]}"
  [[ -n "${config[output_format]:-}" ]] && OUTPUT_FORMAT="${config[output_format]}"
  [[ -n "${config[output_file]:-}" ]] && OUTPUT_FILE="${config[output_file]}"
  [[ -n "${config[pre_release_id]:-}" ]] && pre_release_id="${config[pre_release_id]}"
  
  # Exporte les branches de production pour les fonctions internes
  export PRODUCTION_BRANCHES="$production_branches"
  
  # Définir le fichier de sortie par défaut si non spécifié
  if [[ -z "$OUTPUT_FILE" ]]; then
    case "$OUTPUT_FORMAT" in
      dotenv) OUTPUT_FILE=".env" ;;
      json)   OUTPUT_FILE="version-info.json" ;;
      plain)  OUTPUT_FILE="version-info.txt" ;;
      yaml)   OUTPUT_FILE="version-info.yaml" ;;
      xml)    OUTPUT_FILE="version-info.xml" ;;
    esac
  fi
  
  # Valide les paramètres
  if ! validate_input_params "$snapshot_mode" "$bump" "$OUTPUT_FORMAT" "$pre_release_id"; then
    exit $EXIT_INVALID_PARAM
  fi
  
  # Crée/initialise le fichier de sortie si nécessaire
  if [[ -n "$OUTPUT_FILE" && "$OUTPUT_FORMAT" != "github" ]]; then
    # Vérifie si le répertoire existe, le crée si nécessaire
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    if [[ "$output_dir" != "." && ! -d "$output_dir" ]]; then
      mkdir -p "$output_dir" || {
        log_error "Impossible de créer le répertoire de sortie: $output_dir"
        exit $EXIT_PERMISSION_ERROR
      }
    fi
    
    # Initialise le fichier (vide ou avec en-tête JSON/XML)
    case "$OUTPUT_FORMAT" in
      json)
        echo "{" > "$OUTPUT_FILE"
        ;;
      xml)
        echo '<?xml version="1.0" encoding="UTF-8"?>' > "$OUTPUT_FILE"
        echo '<version-info>' >> "$OUTPUT_FILE"
        ;;
      *)
        # Pour dotenv, yaml et plain, vide simplement le fichier
        > "$OUTPUT_FILE"
        ;;
    esac
    
    # Vérifie les permissions d'écriture
    if [[ ! -w "$OUTPUT_FILE" ]]; then
      log_error "Impossible d'écrire dans le fichier de sortie: $OUTPUT_FILE"
      exit $EXIT_PERMISSION_ERROR
    fi
  fi
  
  # Extrait la version actuelle
  local version
  if ! version=$(get_current_version "$gradle_properties_path" "$version_file_path" "$custom_version"); then
    exit $EXIT_GENERAL_ERROR
  fi
  
  # Valide la version extraite
  if ! validate_semantic_version "$version" true; then
    exit $EXIT_INVALID_VERSION
  fi
  
  # Applique le bump si demandé
  if [[ -n "$bump" ]]; then
    local bumped_version
    if ! bumped_version=$(bump_version "$version" "$bump" "$pre_release_id"); then
      exit $EXIT_INVALID_BUMP
    fi
    version="$bumped_version"
    
    # Revalide après le bump
    if ! validate_semantic_version "$version"; then
      exit $EXIT_INVALID_VERSION
    fi
  fi
  
  # Analyse les composants de la version
  local -A components=()
  if ! parse_version_components "$version" components; then
    exit $EXIT_INVALID_VERSION
  fi
  
  # Détermine si c'est un snapshot
  local is_snapshot
  is_snapshot=$(determine_snapshot_mode "$version" "$snapshot_mode")
  
  # Construit le nom de version final
  local version_name
  
  # Pour la simplicité, supprimez d'abord tout suffixe SNAPSHOT existant
  local clean_version="${components[major]}.${components[minor]}.${components[patch]}"
  local prerelease="${components[prerelease]}"
  local buildmeta="${components[buildmeta]}"
  
  # Le prerelease doit exclure SNAPSHOT (qui est ajouté séparément selon is_snapshot)
  prerelease=${prerelease//SNAPSHOT/}
  prerelease=${prerelease//-/}
  
  # Reconstruit la version avec ou sans SNAPSHOT selon le mode
  if [[ "$is_snapshot" == "true" ]]; then
    if [[ -n "$prerelease" ]]; then
      version_name="${clean_version}-${prerelease}-SNAPSHOT"
    else
      version_name="${clean_version}-SNAPSHOT"
    fi
  else
    if [[ -n "$prerelease" ]]; then
      version_name="${clean_version}-${prerelease}"
    else
      version_name="${clean_version}"
    fi
  fi
  
  # Ajoute buildmeta si présent
  [[ -n "$buildmeta" ]] && version_name="${version_name}+${buildmeta}"
  
  # Construction de la version complète avec préfixe
  local full_version="${version_prefix}${version_name}"
  local is_release=$([[ "$is_snapshot" == "false" ]] && echo "true" || echo "false")
  
  # Calcul du version code
  local version_code
  version_code=$(calculate_version_code "${components[major]}" "${components[minor]}" "${components[patch]}")
  
  # Obtention des valeurs supplémentaires
  local build_date git_commit
  build_date=$(get_build_date) || exit $EXIT_DATE_ERROR
  git_commit=$(get_git_commit)
  
  # Écriture des sorties
  write_output "version"      "$full_version"
  write_output "version_name" "$version_name"
  write_output "version_code" "$version_code"
  write_output "major"        "${components[major]}"
  write_output "minor"        "${components[minor]}"
  write_output "patch"        "${components[patch]}"
  write_output "is_snapshot"  "$is_snapshot"
  write_output "is_release"   "$is_release"
  write_output "build_date"   "$build_date"
  write_output "git_commit"   "$git_commit"
  
  # Finalisation des formats composites
  if [[ "$OUTPUT_FORMAT" =~ ^(json|yaml|xml)$ ]]; then
    generate_output_file
  fi
  
  # Affichage du résumé
  log_success "Version extraite: $full_version"
  log_info "Version numérique: $version_code"
  log_info "Est un snapshot: $is_snapshot"
  log_info "Est une release: $is_release"
  
  if [[ -n "$OUTPUT_FILE" && "$OUTPUT_FORMAT" != "github" ]]; then
    log_info "Sortie écrite dans $OUTPUT_FILE"
  fi
  
  return $EXIT_SUCCESS
}

# N'exécute main que si lancé directement (pas si sourcé)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi