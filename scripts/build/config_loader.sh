#!/usr/bin/env bash
#
# BSSG - Configuration Loader
# Sets default variables, loads user config and locale files, and exports them.
#

# --- Default Configuration Variables ---
# Use :- syntax to only set defaults if the variable is unset or null.
# This allows values set by CLI parsing (before this script is sourced) to persist.
CONFIG_FILE="${CONFIG_FILE:-config.sh}"
SRC_DIR="${SRC_DIR:-src}"
OUTPUT_DIR="${OUTPUT_DIR:-output}"
TEMPLATES_DIR="${TEMPLATES_DIR:-templates}"
THEMES_DIR="${THEMES_DIR:-themes}"
STATIC_DIR="${STATIC_DIR:-static}"
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
CLEAN_OUTPUT="${CLEAN_OUTPUT:-false}"
FORCE_REBUILD="${FORCE_REBUILD:-false}"
SITE_LANG="${SITE_LANG:-en}"
LOCALE_DIR="${LOCALE_DIR:-locales}"
PAGES_DIR="${PAGES_DIR:-pages}"
MARKDOWN_PROCESSOR="${MARKDOWN_PROCESSOR:-pandoc}"
MARKDOWN_PL_PATH="${MARKDOWN_PL_PATH:-}"
ENABLE_ARCHIVES="${ENABLE_ARCHIVES:-true}"
URL_SLUG_FORMAT="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
PAGE_URL_FORMAT="${PAGE_URL_FORMAT:-slug}"

# --- Configuration and Locale Sourcing Logic --- START ---
# Load main configuration file (using variable potentially set by CLI)
# If CONFIG_FILE wasn't exported by main.sh before sourcing this, it will use the default set above.
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null disable=SC1090,SC1091
    source "$CONFIG_FILE"
    echo -e "${GREEN}Configuration loaded from $CONFIG_FILE${NC}"
else
    echo -e "${YELLOW}Configuration file '$CONFIG_FILE' not found, using defaults.${NC}"
fi

# Check for local override config file (relative to the main config file)
LOCAL_CONFIG_OVERRIDE="${CONFIG_FILE}.local"
if [ -f "$LOCAL_CONFIG_OVERRIDE" ]; then
    # shellcheck source=/dev/null disable=SC1090,SC1091
    source "$LOCAL_CONFIG_OVERRIDE"
    echo -e "${GREEN}Local configuration loaded from ${LOCAL_CONFIG_OVERRIDE}${NC}"
fi

# --- Handle Random Theme --- START ---
# NOTE: This logic was moved to main.sh to run AFTER CLI argument parsing
# Check if theme is set to random after loading configs
# if [[ "${THEME:-default}" == "random" ]]; then
#     echo -e "${YELLOW}Theme set to random, selecting a random theme...${NC}"
#     # Find available themes (directories in THEMES_DIR)
#     local available_themes=()
#     if [ -d "${THEMES_DIR:-themes}" ]; then
#         for d in "${THEMES_DIR:-themes}"/*; do
#             if [ -d "$d" ]; then
#                 local theme_name=$(basename "$d")
#                 # Exclude "random" itself if it exists as a directory
#                 if [[ "$theme_name" != "random" ]]; then
#                     available_themes+=("$theme_name")
#                 fi
#             fi
#         done
#     fi
#     
#     local num_themes=${#available_themes[@]}
#     if [ "$num_themes" -gt 0 ]; then
#         # Select a random theme index
#         local random_index=$(( RANDOM % num_themes ))
#         THEME="${available_themes[$random_index]}"
#         echo -e "${GREEN}Randomly selected theme: $THEME${NC}"
#     else
#         echo -e "${RED}Error: No themes found in '$THEMES_DIR' to select randomly. Defaulting to 'default'.${NC}"
#         THEME="default"
#     fi
# fi
# --- Handle Random Theme --- END ---

# ---- Start Locale Loading ----
# Function to print error messages in red (specific to locale loading)
print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

# Set the path for the locale file based on SITE_LANG
LOCALE_FILE="${LOCALE_DIR}/${SITE_LANG}.sh"
DEFAULT_LOCALE_FILE="${LOCALE_DIR}/en.sh"

# Check if the specific locale file exists
if [ -f "$LOCALE_FILE" ]; then
    echo "Loading locale: ${SITE_LANG} from ${LOCALE_FILE}"
    # shellcheck source=/dev/null disable=SC1090
    . "$LOCALE_FILE"
elif [ -f "$DEFAULT_LOCALE_FILE" ]; then
    echo -e "${YELLOW}Warning: Locale file '${LOCALE_FILE}' not found. Defaulting to English.${NC}"
    echo "Loading locale: en from ${DEFAULT_LOCALE_FILE}"
    # shellcheck source=/dev/null disable=SC1090
    . "$DEFAULT_LOCALE_FILE"
else
    print_error "Default locale file '${DEFAULT_LOCALE_FILE}' not found."
    print_error "Please ensure '${LOCALE_DIR}/en.sh' exists."
    exit 1
fi
# ---- End Locale Loading ----
# --- Configuration and Locale Sourcing Logic --- END ---


# --- Export All Variables --- START ---

# Define the list of configuration variables relevant for hashing/exporting
# Ensure this list includes ALL variables that could be set in config.sh or config.sh.local
# and that should trigger a cache rebuild if changed.
BSSG_CONFIG_VARS_ARRAY=(
    CONFIG_FILE SRC_DIR OUTPUT_DIR TEMPLATES_DIR THEMES_DIR STATIC_DIR THEME
    SITE_TITLE SITE_DESCRIPTION SITE_URL AUTHOR_NAME AUTHOR_EMAIL
    DATE_FORMAT TIMEZONE SHOW_TIMEZONE POSTS_PER_PAGE RSS_ITEM_LIMIT CLEAN_OUTPUT
    FORCE_REBUILD SITE_LANG LOCALE_DIR PAGES_DIR MARKDOWN_PROCESSOR
    MARKDOWN_PL_PATH ENABLE_ARCHIVES URL_SLUG_FORMAT PAGE_URL_FORMAT
    # Add any other custom config variables here if needed
)

# Convert array to space-separated string for export
BSSG_CONFIG_VARS="${BSSG_CONFIG_VARS_ARRAY[@]}"
export BSSG_CONFIG_VARS

# Export all config variables individually as well, for direct use by scripts
# This might seem redundant, but ensures compatibility if scripts expect individual vars
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
export CLEAN_OUTPUT
export FORCE_REBUILD
export SITE_LANG
export LOCALE_DIR
export PAGES_DIR
export MARKDOWN_PROCESSOR
export MARKDOWN_PL_PATH
export ENABLE_ARCHIVES
export URL_SLUG_FORMAT
export PAGE_URL_FORMAT

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