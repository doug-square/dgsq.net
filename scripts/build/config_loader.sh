#!/usr/bin/env bash
#
# BSSG - Configuration Loader
# Sets default variables, loads user config and locale files, and exports them.
#

# Capture the command-line config file path, if provided by the main script.
CMD_LINE_CONFIG_FILE="$1"
shift || true # Shift arguments even if only one was passed (or none)

# --- Default Configuration Variables --- START ---
# Use :- syntax to only set defaults if the variable is unset or null.
# This allows values set by CLI parsing (before this script is sourced) to persist.
CONFIG_FILE="${CONFIG_FILE:-config.sh}"
SRC_DIR="${SRC_DIR:-src}"
OUTPUT_DIR="${OUTPUT_DIR:-output}"
TEMPLATES_DIR="${TEMPLATES_DIR:-templates}"
THEMES_DIR="${THEMES_DIR:-themes}"
STATIC_DIR="${STATIC_DIR:-static}"
CACHE_DIR="${CACHE_DIR:-.bssg_cache}" # Default cache directory
THEME="${THEME:-default}"
SITE_TITLE="${SITE_TITLE:-My Journal}"
SITE_DESCRIPTION="${SITE_DESCRIPTION:-A personal journal and introspective newspaper}"
SITE_URL="${SITE_URL:-http://localhost}"
AUTHOR_NAME="${AUTHOR_NAME:-Anonymous}"
AUTHOR_EMAIL="${AUTHOR_EMAIL:-anonymous@example.com}"
DATE_FORMAT="${DATE_FORMAT:-%Y-%m-%d %H:%M:%S}"
TIMEZONE="${TIMEZONE:-local}"
SHOW_TIMEZONE="${SHOW_TIMEZONE:-false}"
POSTS_PER_PAGE="${POSTS_PER_PAGE:-10}"
RSS_ITEM_LIMIT="${RSS_ITEM_LIMIT:-15}" # Default RSS item limit
RSS_INCLUDE_FULL_CONTENT="${RSS_INCLUDE_FULL_CONTENT:-false}" # Default RSS full content
RSS_FILENAME="${RSS_FILENAME:-rss.xml}" # Default RSS filename
INDEX_SHOW_FULL_CONTENT="${INDEX_SHOW_FULL_CONTENT:-false}" # Default: show excerpt on homepage
CLEAN_OUTPUT="${CLEAN_OUTPUT:-false}"
FORCE_REBUILD="${FORCE_REBUILD:-false}"
BUILD_MODE="${BUILD_MODE:-normal}" # Build mode: normal or ram
SITE_LANG="${SITE_LANG:-en}"
LOCALE_DIR="${LOCALE_DIR:-locales}"
PAGES_DIR="${PAGES_DIR:-pages}"
MARKDOWN_PROCESSOR="${MARKDOWN_PROCESSOR:-pandoc}"
MARKDOWN_PL_PATH="${MARKDOWN_PL_PATH:-}"
ENABLE_ARCHIVES="${ENABLE_ARCHIVES:-true}"
URL_SLUG_FORMAT="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
PAGE_URL_FORMAT="${PAGE_URL_FORMAT:-slug}"
ENABLE_TAG_RSS="${ENABLE_TAG_RSS:-false}" # Generate RSS feed for each tag
ENABLE_AUTHOR_PAGES="${ENABLE_AUTHOR_PAGES:-true}" # Generate author index pages
ENABLE_AUTHOR_RSS="${ENABLE_AUTHOR_RSS:-false}" # Generate RSS feed for each author
SHOW_AUTHORS_MENU_THRESHOLD="${SHOW_AUTHORS_MENU_THRESHOLD:-2}" # Minimum authors to show menu

# Related Posts Configuration Defaults
ENABLE_RELATED_POSTS="${ENABLE_RELATED_POSTS:-true}" # Enable or disable related posts feature
RELATED_POSTS_COUNT="${RELATED_POSTS_COUNT:-3}" # Number of related posts to show

# --- Backup Directory --- Added ---
BACKUP_DIR="${BACKUP_DIR:-backup}" # Default backup location

# --- Server Defaults --- Added for 'bssg.sh server' ---
BSSG_SERVER_PORT_DEFAULT="${BSSG_SERVER_PORT_DEFAULT:-8000}"
BSSG_SERVER_HOST_DEFAULT="${BSSG_SERVER_HOST_DEFAULT:-localhost}"

# Customization Defaults
CUSTOM_CSS="${CUSTOM_CSS:-}" # Default to empty string

# Define default colors here so utils.sh can use them if not overridden by config
if [[ -t 1 ]] && command -v tput > /dev/null 2>&1 && tput setaf 1 > /dev/null 2>&1; then
    RED="${RED:-$(tput setaf 1)}"
    GREEN="${GREEN:-$(tput setaf 2)}"
    YELLOW="${YELLOW:-$(tput setaf 3)}"
    BLUE="${BLUE:-$(tput setaf 4)}"
    NC="${NC:-$(tput sgr0)}"
else
    RED="${RED:-}"
    GREEN="${GREEN:-}"
    YELLOW="${YELLOW:-}"
    BLUE="${BLUE:-}"
    NC="${NC:-}"
fi
# --- Default Configuration Variables --- END ---


# --- Source Utilities --- START ---
# Source utility functions (like print_info, print_error) needed by this script.
# Determine the directory of this script
CONFIG_LOADER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
UTILS_SCRIPT="${CONFIG_LOADER_DIR}/utils.sh"

if [ -f "$UTILS_SCRIPT" ]; then
    # shellcheck source=utils.sh
    source "$UTILS_SCRIPT"
    if ! declare -F print_success > /dev/null; then
        echo "Error: Failed to source utils.sh correctly - 'print_success' function not found." >&2
        exit 1
    fi
else
    # Define basic color functions as fallback if utils.sh is missing
    # Needed for messages printed *before* utils.sh is sourced, or if it fails.
    if [[ -t 1 ]] && [[ -z $NO_COLOR ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        NC='\033[0m' # No Color
    else
        RED=""
        GREEN=""
        YELLOW=""
        NC=""
    fi
    print_error() { echo -e "${RED}Error: $1${NC}" >&2; }
    print_warning() { echo -e "${YELLOW}Warning: $1${NC}"; }
    print_success() { echo -e "${GREEN}$1${NC}"; }
    print_info() { echo "Info: $1"; }
    # Print the critical error and exit
    print_error "Utilities script not found at '$UTILS_SCRIPT'. Required by config_loader.sh."
    exit 1
fi
# --- Source Utilities --- END ---


# --- Configuration and Locale Sourcing Logic --- START ---
# Load main configuration file (using variable potentially set by CLI)
# If CONFIG_FILE wasn't exported by main.sh before sourcing this, it will use the default set above.
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null disable=SC1090,SC1091
    source "$CONFIG_FILE"
    print_success "Default configuration loaded from $CONFIG_FILE"
else
    print_warning "Default configuration file '$CONFIG_FILE' not found, using defaults."
fi

# Now, handle the override configuration file
# Prioritize the --config command line argument if provided
if [ -n "$CMD_LINE_CONFIG_FILE" ]; then
    if [ -f "$CMD_LINE_CONFIG_FILE" ]; then
        # shellcheck source=/dev/null disable=SC1090,SC1091
        source "$CMD_LINE_CONFIG_FILE"
        print_success "Command-line configuration loaded from ${CMD_LINE_CONFIG_FILE}"
    else
        print_error "Specified configuration file '${CMD_LINE_CONFIG_FILE}' not found."
        exit 1
    fi
else
    # If --config was not used, check for the default local override file
    LOCAL_CONFIG_OVERRIDE="${CONFIG_FILE}.local"
    if [ -f "$LOCAL_CONFIG_OVERRIDE" ]; then
        # shellcheck source=/dev/null disable=SC1090,SC1091
        source "$LOCAL_CONFIG_OVERRIDE"
        print_success "Local configuration loaded from ${LOCAL_CONFIG_OVERRIDE}"
    # else
        # No local config file found, which is normal. No message needed.
    fi
fi



# ---- Start Locale Loading ----
# Function to print error messages in red (specific to locale loading)
# print_error() {
#     echo -e "${RED}Error: $1${NC}" >&2
# }

# Set the path for the locale file based on SITE_LANG
LOCALE_FILE="${LOCALE_DIR}/${SITE_LANG}.sh"
DEFAULT_LOCALE_FILE="${LOCALE_DIR}/en.sh"

# Check if the specific locale file exists
if [ -f "$LOCALE_FILE" ]; then
    print_info "Loading locale: ${SITE_LANG} from ${LOCALE_FILE}"
    # shellcheck source=/dev/null disable=SC1090
    . "$LOCALE_FILE"
elif [ -f "$DEFAULT_LOCALE_FILE" ]; then
    print_warning "Locale file '${LOCALE_FILE}' not found. Defaulting to English."
    print_info "Loading locale: en from ${DEFAULT_LOCALE_FILE}"
    # shellcheck source=/dev/null disable=SC1090
    . "$DEFAULT_LOCALE_FILE"
else
    print_error "Default locale file '${DEFAULT_LOCALE_FILE}' not found."
    print_error "Please ensure '${LOCALE_DIR}/en.sh' exists."
    exit 1
fi
# ---- End Locale Loading ----
# --- Configuration and Locale Sourcing Logic --- END ---


# --- Define Local Config File Path --- START ---
# Define this *after* main config and local override sourcing, in case CONFIG_FILE was changed.
# Note: LOCAL_CONFIG_OVERRIDE used during sourcing might differ if CONFIG_FILE changed mid-script,
# but we export the path based on the *final* CONFIG_FILE value.
LOCAL_CONFIG_FILE="${CONFIG_FILE}.local"
export LOCAL_CONFIG_FILE # Export it for other scripts
# --- Define Local Config File Path --- END ---


# --- Expand Tilde in Path Variables --- START ---
# After all configs are sourced, expand ~ in relevant paths before exporting.
# This ensures scripts use the resolved paths, even if config stores portable '~'.
print_info "Expanding tilde (~) in configuration paths..."
PATHS_TO_EXPAND=("SRC_DIR" "PAGES_DIR" "DRAFTS_DIR" "OUTPUT_DIR" "TEMPLATES_DIR" "THEMES_DIR" "STATIC_DIR" "BACKUP_DIR" "CACHE_DIR") # Added CACHE_DIR
for var_name in "${PATHS_TO_EXPAND[@]}"; do
    # Get the current value using indirect reference
    current_value="${!var_name}"
    expanded_value=""
    
    # Check if it starts with ~ or ~/ 
    if [[ "$current_value" == "~" ]]; then
        expanded_value="$HOME"
    elif [[ "$current_value" == "~/"* ]]; then
        # Replace ~/ with $HOME/
        expanded_value="$HOME/${current_value#\~/}"
    fi
    
    # If expansion occurred, update the variable in the current shell using printf -v
    if [ -n "$expanded_value" ]; then
        printf -v "$var_name" '%s' "$expanded_value"
        # echo "Expanded $var_name to: ${!var_name}" # Debugging
    fi
done
# --- Expand Tilde in Path Variables --- END ---


# --- Export All Variables --- START ---

# Define the list of configuration variables relevant for hashing/exporting
# Ensure this list includes ALL variables that could be set in config.sh or config.sh.local
# and that should trigger a cache rebuild if changed.
BSSG_CONFIG_VARS_ARRAY=(
    CONFIG_FILE SRC_DIR OUTPUT_DIR TEMPLATES_DIR THEMES_DIR STATIC_DIR THEME
    SITE_TITLE SITE_DESCRIPTION SITE_URL AUTHOR_NAME AUTHOR_EMAIL
    DATE_FORMAT TIMEZONE SHOW_TIMEZONE POSTS_PER_PAGE RSS_ITEM_LIMIT RSS_INCLUDE_FULL_CONTENT RSS_FILENAME
    INDEX_SHOW_FULL_CONTENT
    CLEAN_OUTPUT FORCE_REBUILD BUILD_MODE SITE_LANG LOCALE_DIR PAGES_DIR MARKDOWN_PROCESSOR
    MARKDOWN_PL_PATH ENABLE_ARCHIVES URL_SLUG_FORMAT PAGE_URL_FORMAT
    DRAFTS_DIR REBUILD_AFTER_POST REBUILD_AFTER_EDIT
    CUSTOM_CSS
    ENABLE_TAG_RSS ENABLE_AUTHOR_PAGES ENABLE_AUTHOR_RSS SHOW_AUTHORS_MENU_THRESHOLD
    BACKUP_DIR CACHE_DIR
    DEPLOY_AFTER_BUILD DEPLOY_SCRIPT
    ARCHIVES_LIST_ALL_POSTS
    ENABLE_RELATED_POSTS RELATED_POSTS_COUNT
    PRECOMPRESS_ASSETS
    # Add any other custom config variables here if needed
    BSSG_SERVER_PORT_DEFAULT BSSG_SERVER_HOST_DEFAULT # Server defaults
)

# Convert array to space-separated string for export
BSSG_CONFIG_VARS="${BSSG_CONFIG_VARS_ARRAY[@]}"
export BSSG_CONFIG_VARS

# Export all config variables individually as well, for direct use by scripts
# The values exported here will be the potentially tilde-expanded ones.
export CONFIG_FILE
export SRC_DIR
export OUTPUT_DIR
export TEMPLATES_DIR
export THEMES_DIR
export STATIC_DIR
export THEME
export SITE_TITLE
export SITE_DESCRIPTION
export SITE_URL
export AUTHOR_NAME
export AUTHOR_EMAIL
export DATE_FORMAT
export TIMEZONE
export SHOW_TIMEZONE
export POSTS_PER_PAGE
export RSS_ITEM_LIMIT
export RSS_INCLUDE_FULL_CONTENT
export RSS_FILENAME
export INDEX_SHOW_FULL_CONTENT
export CLEAN_OUTPUT
export FORCE_REBUILD
export BUILD_MODE
export SITE_LANG
export LOCALE_DIR
export PAGES_DIR
export MARKDOWN_PROCESSOR
export MARKDOWN_PL_PATH
export ENABLE_ARCHIVES
export URL_SLUG_FORMAT
export PAGE_URL_FORMAT
export DRAFTS_DIR
export REBUILD_AFTER_POST
export REBUILD_AFTER_EDIT
export CUSTOM_CSS
export ENABLE_TAG_RSS
export ENABLE_AUTHOR_PAGES
export ENABLE_AUTHOR_RSS
export SHOW_AUTHORS_MENU_THRESHOLD
export BACKUP_DIR
export CACHE_DIR
export DEPLOY_AFTER_BUILD
export DEPLOY_SCRIPT
export ARCHIVES_LIST_ALL_POSTS
export ENABLE_RELATED_POSTS
export RELATED_POSTS_COUNT
export PRECOMPRESS_ASSETS

# Server defaults export
export BSSG_SERVER_PORT_DEFAULT
export BSSG_SERVER_HOST_DEFAULT

# Export colors too, as they might be customized in config and needed by scripts
export RED GREEN YELLOW BLUE NC

# Export ALL MSG_* locale variables explicitly
# These are generally NOT included in BSSG_CONFIG_VARS as they don't affect the config hash directly,
# but changes to the locale *file* itself are checked by common_rebuild_check in cache.sh.
export MSG_HOME MSG_TAGS MSG_ARCHIVES MSG_RSS MSG_PAGES
export MSG_PUBLISHED_ON MSG_READING_TIME_TEMPLATE MSG_UPDATED_ON
export MSG_PREVIOUS_POST MSG_NEXT_POST
export MSG_TAG_PAGE_TITLE MSG_ARCHIVE_PAGE_TITLE
export MSG_POSTS_TAGGED_WITH MSG_POSTS_IN_ARCHIVE
export MSG_NO_POSTS_FOUND
export MSG_MINUTE MSG_MINUTES
# Exports needed by generate_index.sh (especially for parallel)
export MSG_LATEST_POSTS MSG_BY MSG_PAGINATION_TITLE MSG_PAGE_INFO_TEMPLATE
export MSG_MONTH_01 MSG_MONTH_02 MSG_MONTH_03 MSG_MONTH_04
export MSG_MONTH_05 MSG_MONTH_06 MSG_MONTH_07 MSG_MONTH_08
export MSG_MONTH_09 MSG_MONTH_10 MSG_MONTH_11 MSG_MONTH_12

# Fallback using compgen (use with caution, might export unintended vars)
# compgen -v MSG_ | while read -r var; do export "$var"; done
# --- Export All Variables --- END --- 

# --- Final Path Adjustments (after all sourcing) --- START ---
# Ensure relevant directory paths are exported if not already absolute.
# ... existing code ...
# --- Final Path Adjustments (after all sourcing) --- END --- 
