#!/usr/bin/env bash
#
# BSSG - Bash Static Site Generator
# Build script to generate the static site
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

set -e

# Fix relative URLs to use SITE_URL
fix_url() {
    local url="$1"
    
    # Skip if URL is already absolute
    if [[ $url == http://* || $url == https://* || $url == //* ]]; then
        echo "$url"
        return
    fi
    
    # Ensure url starts with / for consistency
    if [[ $url != /* ]]; then
        url="/$url"
    fi
    
    # Combine SITE_URL with the path
    local fixed_url="${SITE_URL}${url}"
    
    echo "$fixed_url"
}

# Default configuration file path
CONFIG_FILE="config.sh"

# Default configuration values
SRC_DIR="src"
OUTPUT_DIR="output"
TEMPLATES_DIR="templates"
THEMES_DIR="themes"
STATIC_DIR="static"
THEME="default"
SITE_TITLE="My Journal"
SITE_DESCRIPTION="A personal journal and introspective newspaper"
SITE_URL="http://localhost"
AUTHOR_NAME="Anonymous"
AUTHOR_EMAIL="anonymous@example.com"
DATE_FORMAT="%Y-%m-%d %H:%M:%S"
TIMEZONE="local"
POSTS_PER_PAGE=10
CLEAN_OUTPUT=false
FORCE_REBUILD=false
SITE_LANG="en" # Default language
LOCALE_DIR="locales" # Directory for language files

# Colors for output messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Format a date string according to the configured DATE_FORMAT
format_date() {
    local input_date="$1"
    local formatted_date
    
    # Skip formatting if date is empty
    if [ -z "$input_date" ]; then
        echo "$input_date"
        return
    fi
    
    # Try to format the date using the configured format
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS date formatting
        formatted_date=$(date -j -f "%Y-%m-%d %H:%M:%S" "$input_date" +"$DATE_FORMAT" 2>/dev/null || \
                         date -j -f "%Y-%m-%d" "$input_date" +"$DATE_FORMAT" 2>/dev/null || \
                         echo "$input_date")
    else
        # Linux date formatting
        formatted_date=$(date -d "$input_date" +"$DATE_FORMAT" 2>/dev/null || echo "$input_date")
    fi
    
    echo "$formatted_date"
}

# Format a timestamp to a date string according to the configured DATE_FORMAT
format_date_from_timestamp() {
    local timestamp="$1"
    local formatted_date
    
    # Skip formatting if timestamp is empty
    if [ -z "$timestamp" ]; then
        echo ""
        return
    fi
    
    # Format the timestamp differently based on OS
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
        # BSD systems (macOS, FreeBSD, etc.)
        formatted_date=$(date -r "$timestamp" +"$DATE_FORMAT" 2>/dev/null || echo "")
    else
        # Linux and other Unix-like systems
        formatted_date=$(date -d "@$timestamp" +"$DATE_FORMAT" 2>/dev/null || echo "")
    fi
    
    echo "$formatted_date"
}

# Generate a URL-friendly slug from a title
generate_slug() {
    local title="$1"
    
    # Convert to lowercase
    local slug=$(echo "$title" | tr '[:upper:]' '[:lower:]')
    
    # First use iconv to transliterate if available
    if command -v iconv >/dev/null 2>&1; then
        slug=$(echo "$slug" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || echo "$slug")
    fi
    
    # Replace all non-alphanumeric characters with hyphens
    slug=$(echo "$slug" | sed -e 's/[^a-z0-9]/-/g')
    
    # Replace multiple consecutive hyphens with a single one
    slug=$(echo "$slug" | sed -e 's/--*/-/g')
    
    # Remove leading and trailing hyphens
    slug=$(echo "$slug" | sed -e 's/^-//' -e 's/-$//')
    
    # If slug is empty, use 'untitled' as fallback
    if [ -z "$slug" ]; then
        slug="untitled"
    fi
    
    echo "$slug"
}

# Cache directory
CACHE_DIR=".bssg_cache"
CONFIG_HASH_FILE="$CACHE_DIR/config_hash.md5"
TEMPLATE_CACHE_DIR="$CACHE_DIR/templates"
THEME_CACHE_DIR="$CACHE_DIR/themes"
STATIC_CACHE_DIR="$CACHE_DIR/static"

# Global variables for templates
HEADER_TEMPLATE=""
FOOTER_TEMPLATE=""
POST_TEMPLATE=""
PAGE_TEMPLATE=""
INDEX_TEMPLATE=""
TAG_TEMPLATE=""
ARCHIVE_TEMPLATE=""

# Global template cache
declare -A TEMPLATE_CACHE

# Template loading function with caching
load_template() {
    local template_path="$1"
    local template_name="$2"
    
    # Check if template is already in memory cache
    if [[ -n "${TEMPLATE_CACHE[$template_name]}" ]]; then
        echo "${TEMPLATE_CACHE[$template_name]}"
        return 0
    fi
    
    # Check if template exists
    if [[ ! -f "$template_path" ]]; then
        echo -e "${RED}Error: Template $template_path not found${NC}" >&2
        return 1
    fi
    
    # Load template
    local template_content="$(<"$template_path")"
    
    # Cache the template in memory
    TEMPLATE_CACHE["$template_name"]="$template_content"
    
    # Return template content
    echo "$template_content"
}

# Function to pre-load all templates
preload_templates() {
    # Create template cache directory if it doesn't exist
    mkdir -p "$TEMPLATE_CACHE_DIR"
    
    local template_dir
    local templates_to_load=("header.html" "footer.html" "post.html" "page.html" "index.html" "tag.html" "archive.html")
    
    # Check if templates are in the theme subdirectory or directly in templates dir
    if [ -d "$TEMPLATES_DIR/$THEME" ]; then
        template_dir="$TEMPLATES_DIR/$THEME"
    else
        template_dir="$TEMPLATES_DIR"
    fi
    
    echo -e "${GREEN}Loading and caching templates from $template_dir${NC}"
    
    # Load each template once
    for tmpl in "${templates_to_load[@]}"; do
        if [ -f "$template_dir/$tmpl" ]; then
            local content
            content=$(load_template "$template_dir/$tmpl" "$tmpl")
            
            # Store the template in the appropriate global variable
            case "$tmpl" in
                "header.html")
                    HEADER_TEMPLATE="$content"
                    ;;
                "footer.html")
                    FOOTER_TEMPLATE="$content"
                    ;;
                "post.html")
                    POST_TEMPLATE="$content"
                    ;;
                "page.html")
                    PAGE_TEMPLATE="$content"
                    ;;
                "index.html")
                    INDEX_TEMPLATE="$content"
                    ;;
                "tag.html")
                    TAG_TEMPLATE="$content"
                    ;;
                "archive.html")
                    ARCHIVE_TEMPLATE="$content"
                    ;;
            esac
        fi
    done
    
    # Generate dynamic menu items from pages
    local menu_items="<a href=\"${SITE_URL}/\">${MSG_HOME:-"Home"}</a>"
    local footer_items="<a href=\"${SITE_URL}/\">${MSG_HOME:-"Home"}</a> &middot;"
    
    # Arrays to store primary and secondary pages
    # Ensure we reset the global arrays before populating
    primary_pages=() # Operate on the global array
    SECONDARY_PAGES=()  # Reset global array
    
    # Scan pages directory for markdown and HTML files
    if [ -d "$PAGES_DIR" ]; then
        local page_files
        page_files=($(find "$PAGES_DIR" -type f \( -name "*.md" -o -name "*.html" \) | sort))
        
        for file in "${page_files[@]}"; do
            # Skip if file is hidden
            if [[ $(basename "$file") == .* ]]; then
                continue
            fi
            
            # Extract title, slug, date, and secondary flag
            local title slug date secondary
            if [[ "$file" == *.html ]]; then
                title=$(grep -m 1 '<title>' "$file" | sed 's/<[^>]*>//g')
                slug=$(grep -m 1 'meta name="slug"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
                date=$(grep -m 1 'meta name="date"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/') # Extract date from meta
                secondary=$(grep -m 1 'meta name="secondary"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
            else
                title=$(parse_metadata "$file" "title")
                slug=$(parse_metadata "$file" "slug")
                date=$(parse_metadata "$file" "date") # Extract date from frontmatter
                secondary=$(parse_metadata "$file" "secondary")
            fi
            
            # If no slug is specified, generate from filename
            if [ -z "$slug" ]; then
                slug=$(basename "$file" | sed 's/\.[^.]*$//')
            fi
            
            # Create URL based on PAGE_URL_FORMAT
            local url="/${PAGE_URL_FORMAT//slug/$slug}/"
            
            # Store page info based on secondary flag (include date)
            if [ "$secondary" = "true" ]; then
                SECONDARY_PAGES+=("$title|${SITE_URL}$url|$date")
            else
                primary_pages+=("$title|${SITE_URL}$url|$date")
            fi
        done
    fi
    
    # Add primary pages to menu
    for page in "${primary_pages[@]}"; do
        IFS='|' read -r title url _ <<< "$page" # Ignore date for menu
        menu_items+=" <a href=\"$url\">$title</a>"
        footer_items+=" <a href=\"$url\">$title</a> &middot;"
    done
    
    # Add Pages menu item if there are secondary pages
    if [ ${#SECONDARY_PAGES[@]} -gt 0 ]; then
        menu_items+=" <a href=\"${SITE_URL}/pages.html\">${MSG_PAGES:-"Pages"}</a>"
        footer_items+=" <a href=\"${SITE_URL}/pages.html\">${MSG_PAGES:-"Pages"}</a> &middot;"
    fi
    
    # Add standard menu items
    menu_items+=" <a href=\"${SITE_URL}/tags/\">${MSG_TAGS:-"Tags"}</a>"
    menu_items+=" <a href=\"${SITE_URL}/archives/\">${MSG_ARCHIVES:-"Archives"}</a>"
    menu_items+=" <a href=\"${SITE_URL}/rss.xml\">${MSG_RSS:-"RSS"}</a>"
    
    footer_items+=" <a href=\"${SITE_URL}/tags/\">${MSG_TAGS:-"Tags"}</a> &middot;"
    footer_items+=" <a href=\"${SITE_URL}/archives/\">${MSG_ARCHIVES:-"Archives"}</a> &middot;"
    footer_items+=" <a href=\"${SITE_URL}/rss.xml\">${MSG_SUBSCRIBE_RSS:-"Subscribe via RSS"}</a>"
    
    # Replace menu placeholders in templates
    HEADER_TEMPLATE=${HEADER_TEMPLATE//\{\{menu_items\}\}/"$menu_items"}
    FOOTER_TEMPLATE=${FOOTER_TEMPLATE//\{\{menu_items\}\}/"$footer_items"}

    # Replace locale placeholders in templates
    # Iterate through all variables starting with MSG_
    for var in $(compgen -v MSG_); do
        # Get the value of the variable
        local value="${!var}"
        # Create the placeholder key (e.g., MSG_HOME -> {{home}})
        # Convert to lowercase and remove MSG_ prefix
        local key="$(echo "${var#MSG_}" | tr '[:upper:]' '[:lower:]')"
        
        # Escape characters special in sed replacement: \, &, and the delimiter |
        local escaped_value=$(echo "$value" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/|/\\|/g')

        # Replace in header, using pipe as delimiter for sed and POSIX whitespace class
        HEADER_TEMPLATE=$(echo "$HEADER_TEMPLATE" | sed "s|{{[[:space:]]*$key[[:space:]]*}}|$escaped_value|g")
        # Replace in footer, using pipe as delimiter for sed and POSIX whitespace class
        FOOTER_TEMPLATE=$(echo "$FOOTER_TEMPLATE" | sed "s|{{[[:space:]]*$key[[:space:]]*}}|$escaped_value|g")
    done

    # Replace language code placeholder using POSIX whitespace class
    HEADER_TEMPLATE=$(echo "$HEADER_TEMPLATE" | sed "s|{{[[:space:]]*site_lang_code[[:space:]]*}}|${SITE_LANG:-en}|g")
}

# Global array for secondary pages
declare -a SECONDARY_PAGES=()
# Global array for primary pages (used for sitemap)
declare -a primary_pages=()

# File locking function
lock_file() {
    local file="$1"
    local lock_file="${file}.lock"
    local max_attempts=10
    local attempt=0
    
    # Try to create the lock file
    while [ $attempt -lt $max_attempts ]; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Successfully created the lock directory
            return 0
        fi
        
        # Wait before trying again
        sleep 0.1
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}Failed to acquire lock for $file after $max_attempts attempts${NC}"
    return 1
}

# Release the lock
unlock_file() {
    local file="$1"
    local lock_file="${file}.lock"
    
    # Remove the lock directory
    rmdir "$lock_file" 2>/dev/null || true
}

# Check for required tools
check_dependencies() {
    local missing_deps=0

    # Array of required commands
    local deps=("awk" "sed" "grep" "find" "date" "md5sum")
    
    # On macOS, md5sum is called md5
    # On OpenBSD, md5sum is also called md5, but with different arguments
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "openbsd"* ]] || [[ "$OSTYPE" == "netbsd"* ]] || [[ "$(uname)" == "OpenBSD" ]] || [[ "$(uname)" == "NetBSD" ]]; then
        if ! command -v md5sum &> /dev/null; then
            if command -v md5 &> /dev/null; then
                # Create an md5sum alias function
                if [[ "$OSTYPE" == "openbsd"* ]] || [[ "$OSTYPE" == "netbsd"* ]] || [[ "$(uname)" == "OpenBSD" ]] || [[ "$(uname)" == "NetBSD" ]]; then
                    # OpenBSD/NetBSD md5 doesn't have -r flag, it outputs "MD5 (file) = hash"
                    md5sum() {
                        if [ $# -eq 0 ] || [ "$1" = "-" ]; then
                            # Handle stdin case
                            md5 | awk '{print $4 "  -"}'
                        else
                            # Handle file arguments
                            md5 "$@" | awk '{print $4 "  " $2}' | sed 's/[()]//g'
                        fi
                    }
                else
                    # macOS version
                    md5sum() {
                        md5 -r "$@" | awk '{print $1 "  " $2}'
                    }
                fi
                export -f md5sum
            else
                echo -e "${RED}Error: Neither md5sum nor md5 is installed${NC}"
                missing_deps=1
            fi
        fi
    fi

    # Add markdown processor dependency based on configuration
    if [ "$MARKDOWN_PROCESSOR" = "pandoc" ]; then
        deps+=("pandoc")
    elif [ "$MARKDOWN_PROCESSOR" = "commonmark" ]; then
        # Check if cmark (commonmark implementation) is installed
        if ! command -v cmark &> /dev/null; then
            echo -e "${RED}Error: commonmark (cmark) is not installed${NC}"
            echo -e "${YELLOW}Tip: Install commonmark/cmark from https://github.com/commonmark/cmark${NC}"
            missing_deps=1
        fi
    elif [ "$MARKDOWN_PROCESSOR" = "markdown.pl" ]; then
        # Check if markdown.pl or Markdown.pl exists in PATH or current directory
        if command -v markdown.pl &> /dev/null; then
            MARKDOWN_PL_PATH="markdown.pl"
        elif command -v Markdown.pl &> /dev/null; then
            MARKDOWN_PL_PATH="Markdown.pl"
        elif [ -f "./markdown.pl" ] && [ -x "./markdown.pl" ]; then
            MARKDOWN_PL_PATH="./markdown.pl"
        elif [ -f "./Markdown.pl" ] && [ -x "./Markdown.pl" ]; then
            MARKDOWN_PL_PATH="./Markdown.pl"
        else
            echo -e "${RED}Error: markdown.pl is not installed or not in PATH${NC}"
            echo -e "${YELLOW}Tip: You can place markdown.pl in the BSSG directory and make it executable${NC}"
            missing_deps=1
        fi
    else
        echo -e "${RED}Error: Invalid MARKDOWN_PROCESSOR value in config. Use 'pandoc', 'commonmark', or 'markdown.pl'.${NC}"
        exit 1
    fi

    echo "Checking dependencies..."

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}Error: $dep is not installed${NC}"
            missing_deps=1
        fi
    done

    # Check for optional GNU parallel
    if command -v parallel &> /dev/null; then
        echo -e "${GREEN}Found GNU parallel, will use for parallel processing${NC}"
        HAS_PARALLEL=true
    else
        echo -e "${YELLOW}GNU parallel not found, using built-in parallel processing fallback${NC}"
        HAS_PARALLEL=false
    fi

    if [ $missing_deps -eq 1 ]; then
        echo -e "${RED}Please install the missing dependencies and try again.${NC}"
        exit 1
    fi

    echo -e "${GREEN}All dependencies installed!${NC}"
}

# Fallback parallel implementation using background processes
# Used when GNU parallel is not available
run_parallel() {
    local max_jobs="$1"
    shift
    
    if [ -z "$max_jobs" ] || [ "$max_jobs" -lt 1 ]; then
        # Determine number of CPU cores if not specified
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            max_jobs=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            max_jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        else
            # Default to 2 jobs if we can't determine
            max_jobs=2
        fi
    fi
    
    local job_count=0
    local pids=()
    
    # Read commands from stdin
    while read -r cmd; do
        # Skip empty lines
        [ -z "$cmd" ] && continue
        
        # If we've reached max jobs, wait for one to finish
        if [ $job_count -ge $max_jobs ]; then
            # Wait for any child process to finish
            wait -n 2>/dev/null || true
            
            # Cleanup finished jobs from pids array
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 $pid 2>/dev/null; then
                    new_pids+=($pid)
                fi
            done
            pids=("${new_pids[@]}")
            
            # Update job count
            job_count=${#pids[@]}
        fi
        
        # Run the command in the background
        (eval "$cmd") &
        pids+=($!)
        job_count=$((job_count + 1))
    done
    
    # Wait for all remaining jobs to finish
    wait
}

# Parallel process files using GNU parallel or built-in fallback
parallel_process() {
    local input_data="$1"
    local process_func="$2"
    local max_jobs="$3"
    local input_type="${4:-lines}"  # Default to processing lines
    
    # Determine number of CPU cores if not specified
    if [ -z "$max_jobs" ] || [ "$max_jobs" -lt 1 ]; then
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            max_jobs=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            max_jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        else
            # Default to 2 jobs if we can't determine
            max_jobs=2
        fi
    fi
    
    echo -e "${GREEN}Processing using $max_jobs parallel jobs${NC}"
    
    if [ "$HAS_PARALLEL" = true ]; then
        # Use GNU parallel
        if [ "$input_type" = "lines" ]; then
            # Process lines from a file or variable
            echo "$input_data" | parallel --jobs "$max_jobs" "$process_func"
        else
            # Process arguments as a list
            parallel --jobs "$max_jobs" "$process_func" ::: $input_data
        fi
    else
        # Use built-in fallback
        if [ "$input_type" = "lines" ]; then
            # Process lines
            echo "$input_data" | while read -r line; do
                echo "$process_func '$line'"
            done | run_parallel "$max_jobs"
        else
            # Process arguments
            for arg in $input_data; do
                echo "$process_func '$arg'"
            done | run_parallel "$max_jobs"
        fi
    fi
}

# Check if src, templates directories exist and create output directory
check_directories() {
    if [ ! -d "$SRC_DIR" ]; then
        echo -e "${RED}Error: Source directory '$SRC_DIR' does not exist${NC}"
        exit 1
    fi

    if [ ! -d "$TEMPLATES_DIR" ]; then
        echo -e "${RED}Error: Templates directory '$TEMPLATES_DIR' does not exist${NC}"
        exit 1
    fi

    if [ ! -d "$THEMES_DIR" ]; then
        echo -e "${RED}Error: Themes directory '$THEMES_DIR' does not exist${NC}"
        exit 1
    fi

    # Create output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/tags"
    mkdir -p "$OUTPUT_DIR/css"
    
    # Create archives directory if archives are enabled
    if [ "$ENABLE_ARCHIVES" = true ]; then
        mkdir -p "$OUTPUT_DIR/archives"
    fi

    # Create cache directory structure
    mkdir -p "$CACHE_DIR"
    mkdir -p "$CACHE_DIR/meta"
    mkdir -p "$CACHE_DIR/content"

    echo -e "${GREEN}Directories verified and created!${NC}"
}

# Create a hash of the current configuration
create_config_hash() {
    echo "Generating configuration hash..."
    
    # Create a string with all configuration variables including theme and language
    local config_string="SRC_DIR=$SRC_DIR
OUTPUT_DIR=$OUTPUT_DIR
TEMPLATES_DIR=$TEMPLATES_DIR
THEMES_DIR=$THEMES_DIR
STATIC_DIR=$STATIC_DIR
THEME=$THEME
SITE_TITLE=$SITE_TITLE
SITE_DESCRIPTION=$SITE_DESCRIPTION
SITE_URL=$SITE_URL
AUTHOR_NAME=$AUTHOR_NAME
AUTHOR_EMAIL=$AUTHOR_EMAIL
DATE_FORMAT=$DATE_FORMAT
TIMEZONE=$TIMEZONE
POSTS_PER_PAGE=$POSTS_PER_PAGE
MARKDOWN_PROCESSOR=$MARKDOWN_PROCESSOR
ENABLE_ARCHIVES=$ENABLE_ARCHIVES
URL_SLUG_FORMAT=$URL_SLUG_FORMAT
PAGE_URL_FORMAT=$PAGE_URL_FORMAT
SITE_LANG=$SITE_LANG"
    
    # Calculate MD5 hash of the config string
    local current_hash=$(echo -n "$config_string" | md5sum | awk '{print $1}')
    
    # Store the hash in the cache file
    echo "$current_hash" > "$CONFIG_HASH_FILE"
    echo -e "Configuration hash created: ${GREEN}$current_hash${NC}"
}

# Check if configuration has changed since last build
config_has_changed() {
    # If no hash file exists, configuration has effectively changed
    if [ ! -f "$CONFIG_HASH_FILE" ]; then
        return 0  # True, config has changed
    fi
    
    # Create a string with all configuration variables EXCEPT theme
    local config_string="SRC_DIR=$SRC_DIR
OUTPUT_DIR=$OUTPUT_DIR
TEMPLATES_DIR=$TEMPLATES_DIR
THEMES_DIR=$THEMES_DIR
STATIC_DIR=$STATIC_DIR
SITE_TITLE=$SITE_TITLE
SITE_DESCRIPTION=$SITE_DESCRIPTION
SITE_URL=$SITE_URL
AUTHOR_NAME=$AUTHOR_NAME
AUTHOR_EMAIL=$AUTHOR_EMAIL
DATE_FORMAT=$DATE_FORMAT
TIMEZONE=$TIMEZONE
POSTS_PER_PAGE=$POSTS_PER_PAGE
MARKDOWN_PROCESSOR=$MARKDOWN_PROCESSOR
ENABLE_ARCHIVES=$ENABLE_ARCHIVES
URL_SLUG_FORMAT=$URL_SLUG_FORMAT
PAGE_URL_FORMAT=$PAGE_URL_FORMAT
SITE_LANG=$SITE_LANG"

    # Create current hash
    local current_hash=$(echo "$config_string" | md5sum | cut -d' ' -f1)
    
    # Read stored hash
    local stored_hash=$(cat "$CONFIG_HASH_FILE")
    
    # Compare hashes
    if [ "$current_hash" != "$stored_hash" ]; then
        echo -e "${YELLOW}Configuration has changed since last build${NC}"
        
        # Store the current non-theme config hash for next time
        echo "$current_hash" > "$CONFIG_HASH_FILE"
        
        return 0  # True, config has changed
    fi
    
    return 1  # False, config has not changed
}

# Check if only the theme has changed (not any other config settings)
only_theme_changed() {
    # If no hash file exists, more than just theme has changed
    if [ ! -f "$CONFIG_HASH_FILE" ] || [ ! -f "$CACHE_DIR/theme.txt" ]; then
        return 1  # False, more than theme has changed
    fi
    
    # Read the stored theme
    local stored_theme=$(cat "$CACHE_DIR/theme.txt")
    
    # Compare current theme with stored theme
    if [ "$THEME" != "$stored_theme" ]; then
        echo -e "${YELLOW}Theme has changed from $stored_theme to $THEME${NC}"
        
        # Store the current theme for next time
        echo "$THEME" > "$CACHE_DIR/theme.txt"
        
        # Check if any other config has changed
        if ! config_has_changed; then
            echo -e "${GREEN}Only theme has changed, will use cache where possible${NC}"
            return 0  # True, only theme has changed
        fi
    fi
    
    return 1  # False, more than theme has changed or theme hasn't changed
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                # Save current settings that may have come from local config
                local saved_theme="$THEME"
                local saved_site_title="$SITE_TITLE"
                local saved_site_url="$SITE_URL"
                local saved_site_description="$SITE_DESCRIPTION"
                local saved_author_name="$AUTHOR_NAME"
                local saved_author_email="$AUTHOR_EMAIL"
                local saved_clean_output="$CLEAN_OUTPUT"

                # Load the specified config file
                CONFIG_FILE="$2"
                if [ -f "$CONFIG_FILE" ]; then
                    # Reset to defaults before loading new config
                    THEME="default"
                    SITE_TITLE="My Journal"
                    SITE_DESCRIPTION="A personal journal and introspective newspaper"
                    SITE_URL="http://localhost"
                    AUTHOR_NAME="Anonymous"
                    AUTHOR_EMAIL="anonymous@example.com"
                    CLEAN_OUTPUT=false

                    # Load new config
                    source "$CONFIG_FILE"
                    echo -e "${GREEN}Configuration loaded from $CONFIG_FILE${NC}"

                    # Load local configuration if it exists
                    local local_config="${CONFIG_FILE}.local"
                    if [ -f "$local_config" ]; then
                        source "$local_config"
                        echo -e "${GREEN}Local configuration loaded from $local_config${NC}"
                    else
                        # If new local config doesn't exist, restore settings from previous local config
                        # but only if they weren't set in the new config file
                        if [ "$THEME" = "default" ] && [ "$saved_theme" != "default" ]; then
                            THEME="$saved_theme"
                        fi
                        if [ "$SITE_TITLE" = "My Journal" ] && [ "$saved_site_title" != "My Journal" ]; then
                            SITE_TITLE="$saved_site_title"
                        fi
                        if [ "$SITE_URL" = "http://localhost" ] && [ "$saved_site_url" != "http://localhost" ]; then
                            SITE_URL="$saved_site_url"
                        fi
                        if [ "$AUTHOR_NAME" = "Anonymous" ] && [ "$saved_author_name" != "Anonymous" ]; then
                            AUTHOR_NAME="$saved_author_name"
                        fi
                        if [ "$AUTHOR_EMAIL" = "anonymous@example.com" ] && [ "$saved_author_email" != "anonymous@example.com" ]; then
                            AUTHOR_EMAIL="$saved_author_email"
                        fi
                        if [ "$CLEAN_OUTPUT" = false ] && [ "$saved_clean_output" != false ]; then
                            CLEAN_OUTPUT="$saved_clean_output"
                        fi
                    fi
                else
                    echo -e "${RED}Error: Configuration file '$CONFIG_FILE' not found${NC}"
                    exit 1
                fi
                shift 2
                ;;
            --src)
                SRC_DIR="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --templates)
                TEMPLATES_DIR="$2"
                shift 2
                ;;
            --theme)
                THEME="$2"
                shift 2
                ;;
            --static)
                STATIC_DIR="$2"
                shift 2
                ;;
            --clean-output)
                # Handle both flag style (--clean-output) and value style (--clean-output true/false)
                if [[ "$2" == "true" || "$2" == "false" ]]; then
                    CLEAN_OUTPUT="$2"
                    shift 2
                else
                    CLEAN_OUTPUT=true
                    shift 1
                fi
                ;;
            --force-rebuild)
                FORCE_REBUILD=true
                shift 1
                ;;
            --site-title)
                SITE_TITLE="$2"
                shift 2
                ;;
            --site-url)
                SITE_URL="$2"
                shift 2
                ;;
            --site-description)
                SITE_DESCRIPTION="$2"
                shift 2
                ;;
            --author-name)
                AUTHOR_NAME="$2"
                shift 2
                ;;
            --author-email)
                AUTHOR_EMAIL="$2"
                shift 2
                ;;
            --posts-per-page)
                POSTS_PER_PAGE="$2"
                shift 2
                ;;
            --local-config)
                # Load the local config file directly
                if [ -f "$2" ]; then
                    source "$2"
                    echo -e "${GREEN}Local configuration loaded from $2${NC}"
                else
                    echo -e "${YELLOW}Warning: Local config file $2 not found${NC}"
                fi
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# Clean stale cache entries
clean_stale_cache() {
    # If FORCE_REBUILD is true, delete the entire cache directory and recreate it
    if [ "$FORCE_REBUILD" = true ]; then
        echo -e "${YELLOW}Force rebuild enabled, deleting entire cache...${NC}"
        rm -rf "$CACHE_DIR"
        mkdir -p "$CACHE_DIR"
        mkdir -p "$CACHE_DIR/meta"
        mkdir -p "$CACHE_DIR/content"
        echo -e "${GREEN}Cache deleted!${NC}"
        return
    fi
    
    echo -e "${YELLOW}Cleaning stale cache entries...${NC}"
    
    # Flag to track if any posts were removed
    local posts_removed=false
    
    # Get list of all source files from both src and pages directories
    local md_files=$(find "$SRC_DIR" "$PAGES_DIR" -type f -name "*.md" 2>/dev/null | sort)
    
    # Get list of all cache meta files
    local cache_files=$(find "$CACHE_DIR/meta" -type f 2>/dev/null | sort)
    
    # Convert markdown file paths to basenames for comparison
    local md_basenames=""
    for file in $md_files; do
        md_basenames="$md_basenames$(basename "$file")\n"
    done
    
    # Check each cache file
    for cache_file in $cache_files; do
        local cache_basename=$(basename "$cache_file")
        
        # Check if corresponding markdown file exists
        if ! echo -e "$md_basenames" | grep -q "^$cache_basename$"; then
            echo -e "Removing stale cache entry for: ${YELLOW}$cache_basename${NC}"
            rm -f "$cache_file"
            
            # Also remove the content cache if it exists
            if [ -f "$CACHE_DIR/content/$cache_basename" ]; then
                rm -f "$CACHE_DIR/content/$cache_basename"
            fi
            
            # Mark that posts were removed
            posts_removed=true
        fi
    done
    
    # If any posts were removed, force regeneration of index, tags, archives, etc.
    if [ "$posts_removed" = true ]; then
        echo -e "${YELLOW}Posts were removed, forcing regeneration of index, tags, archives, sitemap, and RSS feed${NC}"
        # Remove marker files to force regeneration
        rm -f "$CACHE_DIR/tags_index.txt"
        rm -f "$CACHE_DIR/archive_index.txt"
        rm -f "$CACHE_DIR/index_marker"
        rm -f "$OUTPUT_DIR/sitemap.xml"
        rm -f "$OUTPUT_DIR/rss.xml"
        rm -f "$OUTPUT_DIR/index.html"
        
        # Also remove tag and archive pages to force their regeneration
        find "$OUTPUT_DIR/tags" -name "*.html" -type f -delete
        find "$OUTPUT_DIR/archives" -name "*.html" -type f -delete
    fi
    
    echo -e "${GREEN}Cache cleaned!${NC}"
}

# Display help information
show_help() {
    echo "BSSG - Bash Static Site Generator"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --config FILE           Configuration file (default: config.sh)"
    echo "  --src DIR               Source directory containing markdown files (default: src)"
    echo "  --output DIR            Output directory for the generated site (default: output)"
    echo "  --templates DIR         Templates directory (default: templates)"
    echo "  --theme NAME            Theme to use (default: default)"
    echo "  --static DIR            Static directory (default: static)"
    echo "  --clean-output          Clean output directory before building (default: false)"
    echo "  --force-rebuild         Force rebuild of all files regardless of modification time"
    echo "  --site-title TITLE      Site title (default: My Journal)"
    echo "  --site-url URL          Site URL (default: http://localhost)"
    echo "  --site-description DESC Site description (default: A personal journal)"
    echo "  --author-name NAME      Author name (default: Anonymous)"
    echo "  --author-email EMAIL    Author email (default: anonymous@example.com)"
    echo "  --posts-per-page NUM    Posts per page (default: 10)"
    echo "  --local-config FILE     Load local configuration file directly"
    echo "  --help                  Display this help message and exit"
}

# Get file modification time in a portable way
get_file_mtime() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
        # BSD systems
        stat -f "%m" "$file" 2>/dev/null || echo "0"
    else
        # Linux and other Unix-like systems
        stat -c "%Y" "$file" 2>/dev/null || echo "0"
    fi
}

# Check if a rebuild is needed based on common conditions
common_rebuild_check() {
    # Force rebuild if flag is set
    if [ "$FORCE_REBUILD" = true ]; then
        return 0  # Rebuild needed
    fi
    
    # Check if configuration has changed
    if config_has_changed; then
        return 0  # Rebuild needed
    fi
    
    # Check if templates have changed
    local header_template="$TEMPLATES_DIR/header.html"
    local footer_template="$TEMPLATES_DIR/footer.html"
    
    # Also check the active locale file
    local active_locale_file=""
    if [ -f "${LOCALE_DIR}/${SITE_LANG}.sh" ]; then
        active_locale_file="${LOCALE_DIR}/${SITE_LANG}.sh"
    elif [ -f "${LOCALE_DIR}/en.sh" ]; then
        active_locale_file="${LOCALE_DIR}/en.sh"
    fi
    
    if [ -f "$1" ]; then  # $1 is the output file to check against
        local output_time=$(get_file_mtime "$1")
        local header_time=$(get_file_mtime "$header_template")
        local footer_time=$(get_file_mtime "$footer_template")
        local locale_time=$(get_file_mtime "$active_locale_file")
        
        # Force rebuild if any template or the locale file is newer than the output
        if (( header_time > output_time )) || (( footer_time > output_time )) || (( locale_time > output_time )); then
            # If locale file changed, print a message
            if (( locale_time > output_time )); then
                echo -e "${YELLOW}Locale file change detected, forcing rebuild for '$1'${NC}"
            fi
            return 0  # Rebuild needed
        fi
        
        # Return this info to the calling function
        return 2  # Valid output file exists, continue with specific checks
    fi
    
    return 0  # No output file, rebuild needed
}

# Check if a rebuild is needed based on file timestamps and templates
file_needs_rebuild() {
    local input_file="$1"
    local output_file="$2"
    
    # Call the common rebuild check function
    common_rebuild_check "$output_file"
    local common_result=$?
    
    # If common conditions already determined we need to rebuild
    if [ $common_result -eq 0 ]; then
        return 0  # Rebuild needed
    fi
    
    # At this point, output_file exists and is newer than templates
    # Now check if output is newer than input
    local input_time=$(get_file_mtime "$input_file")
    local output_time=$(get_file_mtime "$output_file")
    
    # Skip if output exists and is newer than input
    if (( output_time >= input_time )); then
        return 1  # No rebuild needed
    fi
    
    return 0  # Rebuild needed
}

# Check if tags or indexes need rebuilding
indexes_need_rebuild() {
    # Check common rebuild conditions for the main index file
    local main_index="$OUTPUT_DIR/index.html"
    
    # Call the common rebuild check function
    common_rebuild_check "$main_index"
    local common_result=$?
    
    # If common conditions already determined we need to rebuild
    if [ $common_result -eq 0 ]; then
        return 0  # Rebuild needed
    fi
    
    # Check if any of the index files exist and are up to date
    local index_files=(
        "$OUTPUT_DIR/tags/index.html"
        "$OUTPUT_DIR/archives/index.html"
        "$OUTPUT_DIR/index.html"
        "$OUTPUT_DIR/rss.xml"
        "$OUTPUT_DIR/sitemap.xml"
    )
    
    # Get the latest template time
    local latest_template_time=$(get_file_mtime "$main_index")
    
    # Check if file_index.txt exists and is newer than any of the index files
    local file_index="$CACHE_DIR/file_index.txt"
    if [ -f "$file_index" ]; then
        local file_index_time=$(get_file_mtime "$file_index")
        
        # If file_index is newer than the template times, update latest_template_time
        if (( file_index_time > latest_template_time )); then
            latest_template_time=$file_index_time
        fi
    fi
    
    # Check if frontmatter_changes_marker exists and is newer than any of the index files
    local frontmatter_changes_marker="$CACHE_DIR/frontmatter_changes_marker"
    if [ -f "$frontmatter_changes_marker" ]; then
        local marker_time=$(get_file_mtime "$frontmatter_changes_marker")
        
        # If marker is newer than the previous latest time, update it
        if (( marker_time > latest_template_time )); then
            latest_template_time=$marker_time
            echo -e "${YELLOW}Frontmatter changes detected, indexes need rebuild${NC}"
        fi
    fi
    
    # Also check if metadata cache has changed, which would indicate frontmatter edits
    local meta_cache_dir="$CACHE_DIR/meta"
    if [ -d "$meta_cache_dir" ]; then
        # Find the newest metadata file
        local newest_meta_time=0
        local meta_files=$(find "$meta_cache_dir" -type f 2>/dev/null)
        
        for meta_file in $meta_files; do
            local meta_time=$(get_file_mtime "$meta_file")
            if (( meta_time > newest_meta_time )); then
                newest_meta_time=$meta_time
            fi
        done
        
        # If any metadata file is newer than the latest template time, update latest_template_time
        if (( newest_meta_time > latest_template_time )); then
            latest_template_time=$newest_meta_time
        fi
    fi
    
    # Check if any index file is missing or older than templates or file_index
    for index_file in "${index_files[@]}"; do
        if [ ! -f "$index_file" ] || (( $(get_file_mtime "$index_file") < latest_template_time )); then
            return 0  # Rebuild needed
        fi
    done
    
    return 1  # No rebuild needed
}

# Add a reading time calculation function
calculate_reading_time() {
    local content="$1"

    # Count words
    local word_count
    word_count=$(echo "$content" | wc -w | tr -d ' ')

    # Assuming average reading speed of 200 words per minute
    local reading_time_min=$((word_count / 200))

    # Ensure reading time is at least 1 minute
    if [ "$reading_time_min" -lt 1 ]; then
        reading_time_min=1
    fi

    echo "$reading_time_min"
}

# Parse metadata from a markdown file
parse_metadata() {
    local file="$1"
    local field="$2"

    # Try to get from cache
    local cache_file="$CACHE_DIR/meta/$(basename "$file")"
    local value=""

    # Get locks for cache access
    lock_file "$cache_file"
    
    # Create metadata cache if it doesn't exist
    if [ ! -f "$cache_file" ] || [ "$file" -nt "$cache_file" ]; then
        local start_line=$(grep -n "^---$" "$file" | head -1 | cut -d: -f1)
        local end_line=$(grep -n "^---$" "$file" | head -2 | tail -1 | cut -d: -f1)

        if [ -n "$start_line" ] && [ -n "$end_line" ]; then
            # Extract frontmatter and clean it up
            sed -n "$((start_line+1)),$((end_line-1))p" "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$cache_file"
        fi
    fi

    # Read from cache if it exists
    if [ -f "$cache_file" ]; then
        value=$(grep -m 1 "^$field:" "$cache_file" | cut -d ':' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    
    # Release lock
    unlock_file "$cache_file"

    # Fall back to direct file read if cache fails
    if [ -z "$value" ]; then
        # Extract frontmatter and clean it up
        local start_line=$(grep -n "^---$" "$file" | head -1 | cut -d: -f1)
        local end_line=$(grep -n "^---$" "$file" | head -2 | tail -1 | cut -d: -f1)

        if [ -n "$start_line" ] && [ -n "$end_line" ]; then
            value=$(sed -n "$((start_line+1)),$((end_line-1))p" "$file" | grep -m 1 "^$field:" | cut -d ':' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
    fi

    echo "$value"
}

# Extract metadata from markdown file
extract_metadata() {
    local file="$1"
    local metadata_cache_file="$CACHE_DIR/meta/$(basename "$file")"
    local frontmatter_changes_marker="$CACHE_DIR/frontmatter_changes_marker"
    
    # Check if file exists
    if [ ! -f "$file" ]; then
        echo "ERROR_FILE_NOT_FOUND"
        return 1
    fi
    
    # Flag to track whether frontmatter has changed
    local frontmatter_changed=false
    
    # Check if cache exists and is newer than the source file
    if [ "$FORCE_REBUILD" = false ] && [ -f "$metadata_cache_file" ] && [ "$metadata_cache_file" -nt "$file" ]; then
        # Read from cache file (optimized - read once)
        echo "$(cat "$metadata_cache_file")"
        return 0
    else
        # If we're regenerating metadata, mark that as a frontmatter change
        frontmatter_changed=true
    fi
    
    # If we're here, we need to parse the file
    local title="" date="" tags="" slug="" image="" image_caption="" description="" content=""
    local in_frontmatter=false
    local found_frontmatter=false
    
    # Read the file only once and process line by line
    {
        while IFS= read -r line; do
            if [[ "$line" == "---" ]]; then
                if [ "$in_frontmatter" = false ] && [ "$found_frontmatter" = false ]; then
                    in_frontmatter=true
                    found_frontmatter=true
                    continue
                elif [ "$in_frontmatter" = true ]; then
                    in_frontmatter=false
                    continue
                fi
            fi
            
            if [ "$in_frontmatter" = true ]; then
                # Parse each frontmatter field
                if [[ "$line" =~ ^[[:space:]]*title:[[:space:]]*(.*) ]]; then
                    title="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*date:[[:space:]]*(.*) ]]; then
                    date="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*tags:[[:space:]]*(.*) ]]; then
                    tags="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*slug:[[:space:]]*(.*) ]]; then
                    slug="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*image:[[:space:]]*(.*) ]]; then
                    image="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*image_caption:[[:space:]]*(.*) ]]; then
                    image_caption="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.*) ]]; then
                    description="${BASH_REMATCH[1]}"
                fi
            else
                # If we're not in frontmatter and already processed it, we don't need to read more
                if [ "$found_frontmatter" = true ] && [ "$in_frontmatter" = false ]; then
                    break
                fi
                # Collect the content (for reading time calculation)
                content+="$line"$'\n'
            fi
        done
    } < "$file"
    
    # Set fallbacks for missing metadata
    if [ -z "$title" ]; then
        title=$(basename "$file" | sed 's/\.[^.]*$//')
    fi
    
    if [ -z "$date" ]; then
        # Use standardized get_file_mtime and format_date functions
        local file_mtime=$(get_file_mtime "$file")
        date=$(format_date_from_timestamp "$file_mtime")
    fi
    
    # Generate slug from title if missing
    if [ -z "$slug" ]; then
        slug=$(generate_slug "$title")
    fi
    
    # If description is empty, generate an excerpt from the post content
    if [ -z "$description" ]; then
        description=$(generate_excerpt "$file")
    fi
    
    # Check if there was a previous metadata file
    if [ -f "$metadata_cache_file" ]; then
        # Compare old metadata with new metadata to detect changes
        local old_metadata=$(cat "$metadata_cache_file")
        local new_metadata="$title|$date|$tags|$slug|$image|$image_caption|$description"
        
        if [ "$old_metadata" != "$new_metadata" ]; then
            frontmatter_changed=true
        fi
    fi
    
    # Store all metadata in one write operation
    mkdir -p "$(dirname "$metadata_cache_file")"
    echo "$title|$date|$tags|$slug|$image|$image_caption|$description" > "$metadata_cache_file"
    
    # If frontmatter has changed, update the marker
    if [ "$frontmatter_changed" = true ]; then
        touch "$frontmatter_changes_marker"
    fi
    
    # Return the metadata as pipe-separated values
    echo "$title|$date|$tags|$slug|$image|$image_caption|$description"
}

# Generate an excerpt from post content
generate_excerpt() {
    local file="$1"
    local max_length="${2:-160}"  # Default to 160 characters
    
    # Extract content after frontmatter
    local start_line=$(grep -n "^---$" "$file" | head -1 | cut -d: -f1)
    local end_line=$(grep -n "^---$" "$file" | head -2 | tail -1 | cut -d: -f1)
    
    local content=""
    if [ -z "$start_line" ] || [ -z "$end_line" ]; then
        # No frontmatter, use the beginning of the file
        content=$(head -n 50 "$file")
    else
        # Extract content after frontmatter
        content=$(tail -n +$((end_line + 1)) "$file" | head -n 50)
    fi
    
    # Comprehensive markdown sanitization
    
    # 1. Remove code blocks (both ```code``` and indented)
    content=$(echo "$content" | awk '/^```/{flag=!flag;next} !flag;' | grep -v '^```')
    content=$(echo "$content" | grep -v '^    ')
    
    # Process line by line to handle multiline patterns better
    content=$(echo "$content" | while IFS= read -r line; do
        # 2. Remove images ![alt](url)
        line=$(echo "$line" | sed -E 's/!\[([^]]*)\]\([^)]*\)//g')
        
        # 3. Replace links [text](url) with just text
        line=$(echo "$line" | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g')
        
        # 4. Remove HTML tags
        line=$(echo "$line" | sed -E 's/<[^>]*>//g')
        
        # 5. Remove headers (# Header)
        line=$(echo "$line" | sed -E 's/^#+ +//g')
        
        # 6. Remove emphasis markers (* and _)
        line=$(echo "$line" | sed -E 's/\*\*([^*]+)\*\*/\1/g') # Bold **text**
        line=$(echo "$line" | sed -E 's/__([^_]+)__/\1/g')     # Bold __text__
        line=$(echo "$line" | sed -E 's/\*([^*]+)\*/\1/g')     # Italic *text*
        line=$(echo "$line" | sed -E 's/_([^_]+)_/\1/g')       # Italic _text_
        line=$(echo "$line" | sed -E 's/`([^`]+)`/\1/g')       # Code `text`
        
        # 7. Remove blockquotes (> text)
        line=$(echo "$line" | sed -E 's/^> +//g')
        
        # 8. Remove list markers (* and 1.)
        line=$(echo "$line" | sed -E 's/^(\*|\+|-|[0-9]+\.) +//g')
        
        # 9. Remove horizontal rules
        if ! echo "$line" | grep -qE '^(---|___|\*\*\*)$'; then
            echo "$line"
        fi
    done)
    
    # 10. Normalize whitespace and remove extra line breaks
    content=$(echo "$content" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
    
    # 11. Escape HTML special characters
    content=$(echo "$content" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g')
    
    # Truncate to approximately max_length chars at word boundary
    local truncated=$(echo "$content" | awk "length > $max_length {print substr(\$0,1,$max_length); sub(/[^ ]*$/,\"\"); print \$0; exit} {print}")
    
    # If we truncated the text, add ellipsis
    if [ "$truncated" != "$content" ]; then
        truncated="${truncated}..."
    fi
    
    echo "$truncated"
}

# Convert markdown to HTML
convert_markdown() {
    local input_file="$1"
    local output_base_path="$2"
    local title="$3"
    local date="$4"
    local tags="$5"
    local slug="$6"
    local image="$7"
    local image_caption="$8"
    local description="$9"
    local content_cache_file="$CACHE_DIR/content/$(basename "$input_file")"
    
    # Check if the source file exists
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: Source file '$input_file' not found${NC}"
        return 1
    fi
    
    # Skip if output file is newer than input file and no force rebuild
    if [ "$FORCE_REBUILD" = false ] && [ -f "$output_base_path/index.html" ]; then
        local src_mtime=$(get_file_mtime "$input_file")
        local out_mtime=$(get_file_mtime "$output_base_path/index.html")
        
        if [ "$out_mtime" -ge "$src_mtime" ]; then
            echo -e "Skipping unchanged file: ${YELLOW}$(basename "$input_file")${NC}"
            return 0
        fi
    fi
    
    # Try to get content from cache
    local content=""
    if [ "$FORCE_REBUILD" = false ] && [ -f "$content_cache_file" ] && [ "$content_cache_file" -nt "$input_file" ]; then
        content=$(cat "$content_cache_file")
    else
        # Extract content from source file
        local in_frontmatter=false
        local found_frontmatter=false
        
        # Read the file only once and process line by line
        {
            while IFS= read -r line; do
                if [[ "$line" == "---" ]]; then
                    if [ "$in_frontmatter" = false ] && [ "$found_frontmatter" = false ]; then
                        in_frontmatter=true
                        found_frontmatter=true
                        continue
                    elif [ "$in_frontmatter" = true ]; then
                        in_frontmatter=false
                        continue
                    fi
                fi
                
                # Only collect content when not in frontmatter
                if [ "$in_frontmatter" = false ]; then
                    content+="$line"$'\n'
                fi
            done
        } < "$input_file"
        
        # If no frontmatter was found, use the whole file as content
        if [ "$found_frontmatter" = false ]; then
            content=$(cat "$input_file")
        fi
        
        # Cache the content
        mkdir -p "$(dirname "$content_cache_file")"
        echo "$content" > "$content_cache_file"
    fi

    # Calculate reading time once
    local reading_time
    reading_time=$(calculate_reading_time "$content")

    # Convert markdown to HTML using the configured processor
    local html_content
    if [ "$MARKDOWN_PROCESSOR" = "pandoc" ]; then
        if ! html_content=$(echo "$content" | pandoc -f markdown -t html); then
            echo -e "${RED}Error: Markdown conversion failed for $input_file${NC}"
            return 1
        fi
    elif [ "$MARKDOWN_PROCESSOR" = "commonmark" ]; then
        if ! html_content=$(echo "$content" | cmark); then
            echo -e "${RED}Error: Markdown conversion failed for $input_file${NC}"
            return 1
        fi
    elif [ "$MARKDOWN_PROCESSOR" = "markdown.pl" ]; then
        # Preprocess content to handle fenced code blocks for markdown.pl
        # Convert fenced code blocks to indented code blocks that markdown.pl understands
        local preprocessed_content="$content"
        
        # Create a temporary file for preprocessing
        local temp_file=$(mktemp)
        echo "$preprocessed_content" > "$temp_file"
        
        # Handle fenced code blocks with backticks (```) and tildes (~~~)
        # This converts them to standard 4-space indented code blocks
        if command -v awk &> /dev/null; then
            preprocessed_content=$(awk '
                # Flag to track if we are in a code block
                BEGIN { in_code = 0; language = ""; }
                
                # Detect start of a fenced code block (backticks or tildes)
                /^```[a-zA-Z0-9]*$/ || /^~~~[a-zA-Z0-9]*$/ {
                    if (!in_code) {
                        in_code = 1;
                        # Extract language if present
                        language = $0;
                        sub(/^```/, "", language);
                        sub(/^~~~/, "", language);
                        # Print a blank line before the code block
                        print "";
                        next;
                    }
                }
                
                # Detect end of a fenced code block
                /^```$/ || /^~~~$/ {
                    if (in_code) {
                        in_code = 0;
                        # Print a blank line after the code block
                        print "";
                        next;
                    }
                }
                
                # Inside a code block, indent with 4 spaces
                {
                    if (in_code) {
                        print "    " $0;
                    } else {
                        print $0;
                    }
                }
            ' "$temp_file")
            
            # Clean up
            rm "$temp_file"
        fi
        
        if ! html_content=$(echo "$preprocessed_content" | perl "$MARKDOWN_PL_PATH"); then
            echo -e "${RED}Error: Markdown conversion failed for $input_file${NC}"
            return 1
        fi
    fi

    # Create HTML tags for tags
    local tags_html=""
    if [ -n "$tags" ]; then
        tags_html="<div class=\"tags\">\n"
        IFS=',' read -ra TAG_ARRAY <<< "$tags"
        for tag in "${TAG_ARRAY[@]}"; do
            # Remove leading/trailing whitespace
            tag=$(echo "$tag" | sed 's/^ *//;s/ *$//')
            # Convert to lowercase and replace spaces with hyphens for the URL
            local tag_slug=$(generate_slug "$tag")
            tags_html+="            <a href=\"${SITE_URL}/tags/$tag_slug.html\" class=\"tag\">$tag</a>\n"
        done
        tags_html+="        </div>"
    fi
    
    # Use pre-loaded templates
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"
    
    # Verify templates are not empty
    if [ -z "$header_content" ] || [ -z "$footer_content" ]; then
        echo -e "${RED}Error: Templates are empty, reload templates${NC}"
        preload_templates
        header_content="$HEADER_TEMPLATE"
        footer_content="$FOOTER_TEMPLATE"
    fi

    # Replace placeholders in the header
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"$title"}
    
    # Set og:type to article for blog posts
    header_content=${header_content//\{\{og_type\}\}/"article"}
    
    # Add page URL for og:url - use the full path structure according to URL_SLUG_FORMAT
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    
    # Extract date components for URL if date is available
    if [ -n "$date" ]; then
        # Extract year, month, day from the date
        local year=$(echo "$date" | cut -d'-' -f1)
        local month=$(echo "$date" | cut -d'-' -f2)
        local day=$(echo "$date" | cut -d'-' -f3 | cut -d' ' -f1)
        
        # Create the URL path according to URL_SLUG_FORMAT
        local page_url=""
        case "$URL_SLUG_FORMAT" in
            "Year/Month/Day/slug")
                page_url="$year/$month/$day/$slug/"
                ;;
            "Year/Month/slug")
                page_url="$year/$month/$slug/"
                ;;
            "Year/slug")
                page_url="$year/$slug/"
                ;;
            *)
                # Default fallback
                page_url="$slug/"
                ;;
        esac
        
        header_content=${header_content//\{\{page_url\}\}/"$page_url"}
    else
        # If no date (like for pages), just use the slug
        header_content=${header_content//\{\{page_url\}\}/"$slug"}
    fi

    # Always use the site description in the header
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    
    # For meta tags, use the post description if available for better SEO
    if [ -n "$description" ]; then
        header_content=${header_content//\{\{og_description\}\}/"$description"}
        header_content=${header_content//\{\{twitter_description\}\}/"$description"}
    else
        header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    fi
    
    # Generate Schema.org JSON-LD for articles
    local schema_json_ld=""
    if [ -n "$date" ]; then
        # Format ISO date for Schema.org
        local iso_date=$(date -d "$date" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$date" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
        
        # Construct image URL if available
        local image_url=""
        if [ -n "$image" ]; then
            if [[ ! "$image" =~ ^https?:// && ! "$image" =~ ^// ]]; then
                image_url="${SITE_URL}${image#/}"
                # Ensure URL has leading slash
                if [[ ! "$image_url" =~ ${SITE_URL}/ ]]; then
                    image_url="${SITE_URL}/${image_url#${SITE_URL}}"
                fi
            else
                image_url="$image"
            fi
        fi
        
        # Create a temporary file for the JSON-LD schema
        local tmp_schema=$(mktemp)
        
        # Write the schema to the temporary file
        cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "$title",
EOF
        
        if [ -n "$description" ]; then
            cat >> "$tmp_schema" << EOF
  "description": "$description",
EOF
        fi
        
        cat >> "$tmp_schema" << EOF
  "datePublished": "$iso_date",
EOF
        
        if [ -n "$image_url" ]; then
            cat >> "$tmp_schema" << EOF
  "image": "$image_url",
EOF
        fi
        
        cat >> "$tmp_schema" << EOF
  "author": {
    "@type": "Person",
    "name": "$AUTHOR_NAME"
EOF
        
        if [ -n "$AUTHOR_EMAIL" ]; then
            cat >> "$tmp_schema" << EOF
,
    "email": "$AUTHOR_EMAIL"
EOF
        fi
        
        cat >> "$tmp_schema" << EOF
  },
  "publisher": {
    "@type": "Organization",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  },
  "mainEntityOfPage": {
    "@type": "WebPage",
    "@id": "$SITE_URL/$page_url"
  }
}
</script>
EOF
        
        # Read the schema from the temporary file
        schema_json_ld=$(cat "$tmp_schema")
        
        # Remove the temporary file
        rm "$tmp_schema"
        
        # Add schema markup to header
        header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}
    else
        # For non-article pages, use WebPage schema
        local tmp_schema=$(mktemp)
        
        # Write the schema to the temporary file
        cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "WebPage",
  "name": "$title",
EOF
        
        if [ -n "$description" ]; then
            cat >> "$tmp_schema" << EOF
  "description": "$description",
EOF
        fi
        
        cat >> "$tmp_schema" << EOF
  "publisher": {
    "@type": "Organization",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  },
  "url": "$SITE_URL/$page_url"
}
</script>
EOF
        
        # Read the schema from the temporary file
        schema_json_ld=$(cat "$tmp_schema")
        
        # Remove the temporary file
        rm "$tmp_schema"
        
        # Add schema markup to header
        header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}
    fi
    
    # Add OpenGraph image if specified
    if [ -n "$image" ]; then
        # Ensure the image URL is absolute
        local img_url="$image"
        if [[ ! "$img_url" =~ ^https?:// && ! "$img_url" =~ ^// ]]; then
            img_url="${SITE_URL}${img_url#/}"
            # Ensure URL has leading slash
            if [[ ! "$img_url" =~ ${SITE_URL}/ ]]; then
                img_url="${SITE_URL}/${img_url#${SITE_URL}}"
            fi
        fi
        
        local og_image_tag="<meta property=\"og:image\" content=\"$img_url\">"
        local twitter_image_tag="<meta name=\"twitter:image\" content=\"$img_url\">"
        
        header_content=${header_content//\{\{og_image\}\}/"$og_image_tag"}
        header_content=${header_content//\{\{twitter_image\}\}/"$twitter_image_tag"}
    else
        # Remove the placeholders if no image
        header_content=${header_content//\{\{og_image\}\}/""}
        header_content=${header_content//\{\{twitter_image\}\}/""}
    fi

    # Replace placeholders in the footer
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

    # Create the complete HTML
    mkdir -p "$output_base_path"
    
    cat > "$output_base_path/index.html" << EOF
$header_content
<div class="page-header">
    <h1 class="page-title">$title</h1>
    ${date:+<div class="page-meta">${MSG_PUBLISHED_ON:-"Published on"} $(format_date "$date") • $(printf "${MSG_READING_TIME_TEMPLATE:-%d min read}" "$reading_time")</div>}
</div>
EOF

    # Add featured image if specified
    if [ -n "$image" ]; then
        cat >> "$output_base_path/index.html" << EOF
<div class="featured-image">
    <img src="$image" alt="${title}" />
    ${image_caption:+<div class="image-caption">$image_caption</div>}
</div>
EOF
    fi

    cat >> "$output_base_path/index.html" << EOF
<div class="page-content">
$html_content
</div>
EOF

    # Add tags if present
    if [ -n "$tags" ]; then
        cat >> "$output_base_path/index.html" << EOF
        <div class="tags">
EOF
        IFS=',' read -ra TAG_ARRAY <<< "$tags"
        for tag in "${TAG_ARRAY[@]}"; do
            # Remove leading/trailing whitespace
            tag=$(echo "$tag" | sed 's/^ *//;s/ *$//')
            # Convert to lowercase and replace spaces with hyphens for the URL
            local tag_slug=$(generate_slug "$tag")
            echo "            <a href=\"${SITE_URL}/tags/$tag_slug.html\" class=\"tag\">$tag</a>" >> "$output_base_path/index.html"
        done
        cat >> "$output_base_path/index.html" << EOF
        </div>
EOF
    fi

    # Add footer
    cat >> "$output_base_path/index.html" << EOF
$footer_content
EOF

    echo -e "Processed: ${GREEN}$(basename "$input_file")${NC}"
}

# Build a simple tags index
build_tags_index() {
    echo -e "${YELLOW}Building tags index...${NC}"
    
    # Check if rebuild is needed
    if ! indexes_need_rebuild && [ -f "$CACHE_DIR/tags_index.txt" ]; then
        # Check if any posts have been added (new posts not in the file_index.txt yet)
        local current_files=$(find "$SRC_DIR" -type f -name "*.md" | wc -l)
        local indexed_files=0
        
        if [ -f "$CACHE_DIR/file_index.txt" ]; then
            indexed_files=$(wc -l < "$CACHE_DIR/file_index.txt")
        fi
        
        # If there are more current files than indexed files, we need to rebuild
        if [ "$current_files" -gt "$indexed_files" ]; then
            echo -e "${YELLOW}New posts detected, rebuilding tags index...${NC}"
        else
            echo -e "${GREEN}Tags index is up to date, skipping...${NC}"
            return
        fi
    fi
    
    local tags_index_file="$CACHE_DIR/tags_index.txt"
    
    # Get lock
    lock_file "$tags_index_file"
    
    > "$tags_index_file"  # Clear the file

    # Create a temporary directory for parallel processing
    local temp_dir="$CACHE_DIR/tags_temp_$$"
    mkdir -p "$temp_dir"

    # Process a batch of index lines for tags
    process_lines_batch_for_tags() {
        local batch_file="$1"
        local output_file="$2"
        
        > "$output_file"  # Initialize empty file
        
        # Read from batch file
        while read -r line; do
            local file filename title date tags slug image image_caption description
            IFS='|' read -r file filename title date tags slug image image_caption description <<< "$line"

            if [ -n "$tags" ]; then
                IFS=',' read -ra TAG_ARRAY <<< "$tags"
                for tag in "${TAG_ARRAY[@]}"; do
                    # Remove leading/trailing whitespace
                    tag=$(echo "$tag" | sed 's/^ *//;s/ *$//')
                    # Convert to lowercase and replace spaces with hyphens for the URL
                    tag_url=$(echo "$tag" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

                    echo "$tag|$tag_url|$title|$date|$filename.html|$slug|$image|$image_caption|$description" >> "$output_file"
                done
            fi
        done < "$batch_file"
    }

    # Use GNU parallel if available, otherwise fallback to sequential processing
    if [ "$HAS_PARALLEL" = true ]; then
        echo -e "${GREEN}Using GNU parallel to process tag index${NC}"
        # Get number of CPU cores
        local cores=1
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            cores=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        fi
        
        # Count total lines in file index
        local total_lines=$(wc -l < "$CACHE_DIR/file_index.txt")
        
        # Split file_index into batches for parallel processing
        split_into_batches() {
            local input_file="$1"
            local batch_size="$2"
            local output_dir="$3"
            local count=0
            local batch=1
            local batch_file="$output_dir/batch_$batch.txt"
            > "$batch_file"  # Initialize empty batch file
            
            cat "$input_file" | while read -r line; do
                echo "$line" >> "$batch_file"
                count=$((count + 1))
                
                if [ $count -ge $batch_size ]; then
                    count=0
                    batch=$((batch + 1))
                    batch_file="$output_dir/batch_$batch.txt"
                    > "$batch_file"  # Initialize next batch file
                fi
            done
        }
        
        # Determine optimal batch size based on total lines and cores
        local batch_size=$(( (total_lines + cores - 1) / cores ))
        [ $batch_size -lt 5 ] && batch_size=5  # Minimum batch size
        
        # Split file index into batches
        split_into_batches "$CACHE_DIR/file_index.txt" $batch_size "$temp_dir"
        
        # Process batches in parallel
        export -f process_lines_batch_for_tags
        
        # Find all batch files and process them in parallel
        find "$temp_dir" -name "batch_*.txt" | parallel --jobs "$cores" "process_lines_batch_for_tags {} $temp_dir/tags_{#}.out"
        
        # Merge all output files
        cat "$temp_dir"/tags_*.out > "$tags_index_file"
        
        # Clean up temp directory
        rm -rf "$temp_dir"
    else
        # Original sequential implementation
        cat "$CACHE_DIR/file_index.txt" | while read -r line; do
            local file filename title date tags slug image image_caption description
            IFS='|' read -r file filename title date tags slug image image_caption description <<< "$line"

            if [ -n "$tags" ]; then
                IFS=',' read -ra TAG_ARRAY <<< "$tags"
                for tag in "${TAG_ARRAY[@]}"; do
                    # Remove leading/trailing whitespace
                    tag=$(echo "$tag" | sed 's/^ *//;s/ *$//')
                    # Convert to lowercase and replace spaces with hyphens for the URL
                    tag_url=$(echo "$tag" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

                    echo "$tag|$tag_url|$title|$date|$filename.html|$slug|$image|$image_caption|$description" >> "$tags_index_file"
                done
            fi
        done
    fi
    
    # Release lock
    unlock_file "$tags_index_file"

    echo -e "${GREEN}Tags index built!${NC}"
}

# Generate sitemap.xml with improved performance
generate_sitemap() {
    echo -e "${YELLOW}Generating sitemap.xml...${NC}"

    local sitemap="$OUTPUT_DIR/sitemap.xml"
    local file_index="$CACHE_DIR/file_index.txt"
    
    # Check if file index exists
    if [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index not found at $file_index${NC}"
        return 1
    fi

    # Skip if sitemap is up to date
    if ! file_needs_rebuild "$file_index" "$sitemap"; then
        echo -e "Skipping unchanged sitemap.xml"
        return
    fi

    # Get current date in YYYY-MM-DD format in a portable way
    local current_date
    if command -v date >/dev/null 2>&1; then
        if date --version >/dev/null 2>&1; then
            # GNU date (Linux)
            current_date=$(date -I)
        else
            # BSD date (MacOS, FreeBSD, etc.)
            current_date=$(date "+%Y-%m-%d")
        fi
    else
        echo -e "${RED}Error: date command not found${NC}"
        return 1
    fi

    # Create sitemap.xml
    cat > "$sitemap" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>${SITE_URL}/</loc>
        <lastmod>${current_date}</lastmod>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
    </url>
    <url>
        <loc>${SITE_URL}/tags/</loc>
        <lastmod>${current_date}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
EOF

    # Add archives URL if enabled
    if [ "$ENABLE_ARCHIVES" = true ]; then
        cat >> "$sitemap" << EOF
    <url>
        <loc>${SITE_URL}/archives/</loc>
        <lastmod>${current_date}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
EOF
    fi

    # Add all posts
    cat "$file_index" | while read -r line; do
        local file filename title date tags slug image image_caption description
        IFS='|' read -r file filename title date tags slug image image_caption description <<< "$line"

        # Skip if essential fields are missing or if it's not a post (e.g., might be a page accidentally indexed)
        # We rely on the date field being present for posts. Pages typically don't have a date.
        if [ -z "$file" ] || [ -z "$title" ] || [ -z "$date" ]; then
            continue
        fi

        # Create output path based on slug format
        # Extract year, month, day from the date
        local year month day post_date_only
        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
            year="${BASH_REMATCH[1]}"
            month="${BASH_REMATCH[2]}"
            day="${BASH_REMATCH[3]}"
            # Ensure month and day have leading zeros
            month=$(printf "%02d" "$(echo "$month" | sed 's/^0*//')")
            day=$(printf "%02d" "$(echo "$day" | sed 's/^0*//')")
            post_date_only="$year-$month-$day" # Use the extracted date for lastmod
        else
            # Default to current date if date format is unrecognized - less ideal
            if command -v date >/dev/null 2>&1; then
                if date --version >/dev/null 2>&1; then # GNU date
                    year=$(date -I | cut -d'-' -f1)
                    month=$(date -I | cut -d'-' -f2)
                    day=$(date -I | cut -d'-' -f3)
                    post_date_only=$(date -I)
                else # BSD date
                    year=$(date "+%Y")
                    month=$(date "+%m")
                    day=$(date "+%d")
                    post_date_only=$(date "+%Y-%m-%d")
                fi
            else
                echo -e "${RED}Error: date command not found, cannot determine post date${NC}"
                post_date_only="$current_date" # Fallback to build date
            fi
        fi
        
        # Apply URL_SLUG_FORMAT to create the output path
        local formatted_path="${URL_SLUG_FORMAT//Year/$year}"
        formatted_path="${formatted_path//Month/$month}"
        formatted_path="${formatted_path//Day/$day}"
        formatted_path="${formatted_path//slug/$slug}"

        # Use the post's date (YYYY-MM-DD) for lastmod
        cat >> "$sitemap" << EOF
    <url>
        <loc>${SITE_URL}/${formatted_path}/</loc>
        <lastmod>${post_date_only}</lastmod> 
        <changefreq>monthly</changefreq>
        <priority>0.7</priority> 
    </url>
EOF
    done

    # Add Primary Pages (Ensure the array is populated before this function runs)
    if [ ${#primary_pages[@]} -gt 0 ]; then
        echo -e "Adding ${#primary_pages[@]} primary pages to sitemap..."
        for page_info in "${primary_pages[@]}"; do
            local title url page_date page_mod_time
            IFS='|' read -r title url page_date <<< "$page_info"

            # Try to use page_date, fallback to current_date
            if [[ "$page_date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                 local year="${BASH_REMATCH[1]}"
                 local month="${BASH_REMATCH[2]}"
                 local day="${BASH_REMATCH[3]}"
                 month=$(printf "%02d" "$(echo "$month" | sed 's/^0*//')")
                 day=$(printf "%02d" "$(echo "$day" | sed 's/^0*//')")
                 page_mod_time="$year-$month-$day"
            else
                 page_mod_time="$current_date" # Fallback to build date
            fi

            cat >> "$sitemap" << EOF
    <url>
        <loc>${url}</loc>
        <lastmod>${page_mod_time}</lastmod> 
        <changefreq>weekly</changefreq>
        <priority>0.8</priority> 
    </url>
EOF
        done
    else
        echo -e "${YELLOW}No primary pages found to add to sitemap.${NC}"
    fi

    # Add Secondary Pages (Ensure the array is populated before this function runs)
    if [ ${#SECONDARY_PAGES[@]} -gt 0 ]; then
        echo -e "Adding ${#SECONDARY_PAGES[@]} secondary pages to sitemap..."
        for page_info in "${SECONDARY_PAGES[@]}"; do
            local title url page_date page_mod_time
            IFS='|' read -r title url page_date <<< "$page_info"

            # Try to use page_date, fallback to current_date
            if [[ "$page_date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                 local year="${BASH_REMATCH[1]}"
                 local month="${BASH_REMATCH[2]}"
                 local day="${BASH_REMATCH[3]}"
                 month=$(printf "%02d" "$(echo "$month" | sed 's/^0*//')")
                 day=$(printf "%02d" "$(echo "$day" | sed 's/^0*//')")
                 page_mod_time="$year-$month-$day"
            else
                 page_mod_time="$current_date" # Fallback to build date
            fi

            cat >> "$sitemap" << EOF
    <url>
        <loc>${url}</loc>
        <lastmod>${page_mod_time}</lastmod>
        <changefreq>monthly</changefreq>
        <priority>0.6</priority> 
    </url>
EOF
        done
    else
        echo -e "${YELLOW}No secondary pages found to add to sitemap.${NC}"
    fi

    # Add tag pages
    find "$OUTPUT_DIR/tags" -type f -name "*.html" | grep -v "index.html" | while read -r file; do
        # Get relative path
        local rel_path=${file#"$OUTPUT_DIR/"}

        # Get file modification time in a portable way
        local mod_time
        if command -v stat >/dev/null 2>&1; then
            if stat --version >/dev/null 2>&1; then
                # GNU stat (Linux)
                mod_time=$(date -I -d @$(stat -c "%Y" "$file"))
            else
                # BSD stat (MacOS, FreeBSD, etc.)
                mod_time=$(stat -f "%Sm" -t "%Y-%m-%d" "$file")
            fi
        else
            # Fallback to perl if available
            if command -v perl >/dev/null 2>&1; then
                mod_time=$(perl -e "print scalar(localtime((stat('$file'))[9])), \"\n\";" | awk '{print $4"-"$2"-"$3}')
            else
                # Last resort: use current date
                mod_time="$current_date"
            fi
        fi

        cat >> "$sitemap" << EOF
    <url>
        <loc>${SITE_URL}/${rel_path}</loc>
        <lastmod>${mod_time}</lastmod>
        <changefreq>weekly</changefreq> 
        <priority>0.4</priority> 
    </url>
EOF
    done

    # Add archive pages if enabled
    if [ "$ENABLE_ARCHIVES" = true ]; then
        find "$OUTPUT_DIR/archives" -type f -name "*.html" | while read -r file; do
            # Get relative path
            local rel_path=${file#"$OUTPUT_DIR/"}
            
            # Get file modification time in a portable way
            local mod_time
            if command -v stat >/dev/null 2>&1; then
                if stat --version >/dev/null 2>&1; then
                    # GNU stat (Linux)
                    mod_time=$(date -I -d @$(stat -c "%Y" "$file"))
                else
                    # BSD stat (MacOS, FreeBSD, etc.)
                    mod_time=$(stat -f "%Sm" -t "%Y-%m-%d" "$file")
                fi
            else
                # Fallback to perl if available
                if command -v perl >/dev/null 2>&1; then
                    mod_time=$(perl -e "print scalar(localtime((stat('$file'))[9])), \"\n\";" | awk '{print $4"-"$2"-"$3}')
                else
                    # Last resort: use current date
                    mod_time="$current_date"
                fi
            fi
            
            cat >> "$sitemap" << EOF
    <url>
        <loc>${SITE_URL}/${rel_path}</loc>
        <lastmod>${mod_time}</lastmod>
        <changefreq>weekly</changefreq> 
        <priority>0.4</priority> 
    </url>
EOF
        done
    fi

    # Close the sitemap
    cat >> "$sitemap" << EOF
</urlset>
EOF

    echo -e "${GREEN}Sitemap generated!${NC}"
}

# Generate RSS feed with improved performance and better HTML handling
generate_rss() {
    echo -e "${YELLOW}Generating RSS feed...${NC}"
    
    local rss="$OUTPUT_DIR/rss.xml"
    local file_index="$CACHE_DIR/file_index.txt"
    local frontmatter_changes_marker="$CACHE_DIR/frontmatter_changes_marker"
    
    # Check if RSS feed needs to be rebuilt
    if [ "$FORCE_REBUILD" = false ] && [ -f "$rss" ]; then
        local rss_time=$(get_file_mtime "$rss")
        local rebuild_needed=false
        
        # Check if file index is newer than RSS feed
        if [ -f "$file_index" ]; then
            local file_index_time=$(get_file_mtime "$file_index")
            if (( file_index_time > rss_time )); then
                rebuild_needed=true
            fi
        fi
        
        # Check if frontmatter_changes_marker is newer than RSS feed
        if [ -f "$frontmatter_changes_marker" ]; then
            local marker_time=$(get_file_mtime "$frontmatter_changes_marker")
            if (( marker_time > rss_time )); then
                rebuild_needed=true
            fi
        fi
        
        # Check if templates have changed
        local header_template="$TEMPLATES_DIR/header.html"
        local footer_template="$TEMPLATES_DIR/footer.html"
        
        if [ -f "$header_template" ]; then
            local header_time=$(get_file_mtime "$header_template")
            if (( header_time > rss_time )); then
                rebuild_needed=true
            fi
        fi
        
        if [ -f "$footer_template" ]; then
            local footer_time=$(get_file_mtime "$footer_template")
            if (( footer_time > rss_time )); then
                rebuild_needed=true
            fi
        fi
        
        # Skip if no rebuild is needed
        if [ "$rebuild_needed" = false ]; then
            echo -e "${GREEN}RSS feed is up to date, skipping...${NC}"
            return 0
        fi
    fi
    
    # Get the current date in RFC 822 format for the feed
    local now
    if [ "$TIMEZONE" = "GMT" ]; then
        now=$(LC_TIME=C date -u "+%a, %d %b %Y %H:%M:%S GMT")
    elif [ "$TIMEZONE" = "local" ]; then
        now=$(LC_TIME=C date "+%a, %d %b %Y %H:%M:%S %z")
    else
        # Use specified timezone
        LC_TIME=C TZ="$TIMEZONE" now=$(date "+%a, %d %b %Y %H:%M:%S %z")
    fi
    
    # Create the RSS feed
    cat > "$rss" << EOF
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
    <title>${MSG_RSS_FEED_TITLE:-${SITE_TITLE} - RSS Feed}</title>
    <link>$SITE_URL</link>
    <description>${MSG_RSS_FEED_DESCRIPTION:-${SITE_DESCRIPTION}}</description>
    <atom:link href="${SITE_URL}/rss.xml" rel="self" type="application/rss+xml" />
    <lastBuildDate>$now</lastBuildDate>
EOF

    # Read file_index.txt for posts, sort by date (newest first)
    cat "$CACHE_DIR/file_index.txt" | sort -t'|' -k4,4r | head -n 20 | while read -r line; do
        # Split the line into fields
        local file filename title date tags slug image image_caption description
        IFS='|' read -r file filename title date tags slug image image_caption description <<< "$line"
        
        # Skip if essential fields are missing
        if [ -z "$file" ] || [ -z "$title" ]; then
            continue
        fi
        
        # Apply URL_SLUG_FORMAT for the URL
        local year month day
        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
            year="${BASH_REMATCH[1]}"
            month="${BASH_REMATCH[2]}"
            day="${BASH_REMATCH[3]}"
            # Remove leading zeros
            month=$(echo "$month" | sed 's/^0*//')
            day=$(echo "$day" | sed 's/^0*//')
            # Ensure leading zeros for formatting
            month=$(printf "%02d" "$month")
            day=$(printf "%02d" "$day")
        else
            # Default to current date
            year=$(date +%Y)
            month=$(date +%m)
            day=$(date +%d)
        fi
        
        # Format the URL path
        local formatted_path="${URL_SLUG_FORMAT//Year/$year}"
        formatted_path="${formatted_path//Month/$month}"
        formatted_path="${formatted_path//Day/$day}"
        formatted_path="${formatted_path//slug/$slug}"
        
        # Format date for RSS
        local rss_date=""
        if [ -n "$date" ]; then
            # Check if date includes time (e.g., YYYY-MM-DD HH:MM:SS or YYYY-MM-DDTHH:MM:SS)
            local date_with_time="$date"
            if ! [[ "$date" =~ [0-9]{4}-[0-9]{1,2}-[0-9]{1,2}[[:space:]T][0-9]{1,2}:[0-9]{1,2}(:[0-9]{1,2})? ]]; then
                # If no time is present, default to midnight (00:00:00)
                date_with_time="$date 00:00:00"
            fi

            # Convert to RFC 822 format for RSS, trying different input formats
            if command -v date > /dev/null 2>&1; then
                local format_string="" 
                if [ "$TIMEZONE" = "local" ]; then
                    format_string="+%a, %d %b %Y %H:%M:%S %z"
                elif [ "$TIMEZONE" = "GMT" ]; then
                    format_string="+%a, %d %b %Y %H:%M:%S GMT"
                    export TZ=GMT # Ensure GMT is used for conversion
                else
                    format_string="+%a, %d %b %Y %H:%M:%S %z"
                    export TZ="$TIMEZONE"
                fi

                # Try converting with GNU date options first, then BSD
                # Use English locale (LC_TIME=C) for consistent month abbreviations
                rss_date=$(LC_TIME=C date -d "$date_with_time" "$format_string" 2>/dev/null || \
                           LC_TIME=C date -j -f "%Y-%m-%d %H:%M:%S" "$date_with_time" "$format_string" 2>/dev/null || \
                           echo "$now") # Fallback to build time
                
                # Unset TZ if it was set
                if [ "$TIMEZONE" != "local" ]; then
                    unset TZ
                fi
            else
                # Fallback if date command is not available
                rss_date="$now"
            fi
        else
            # If no date in frontmatter, use build time
            rss_date="$now"
        fi
        
        # Description is now handled by extract_metadata and may contain an auto-generated excerpt
        # from the beginning of the post if no description was provided in frontmatter
        local content_description="$description"
        
        # Escape description for XML - sanitization already done in generate_excerpt
        # This is a safeguard in case description is from frontmatter and not from generate_excerpt
        description=$(echo "$content_description" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g')

        # Prepare enclosure tag for image if available
        local enclosure_tag=""
        if [ -n "$image" ]; then
            # Ensure the image URL is absolute
            local img_url="$image"
            if [[ ! "$img_url" =~ ^https?:// && ! "$img_url" =~ ^// ]]; then
                img_url="${SITE_URL}${img_url#/}"
                # Ensure URL has leading slash
                if [[ ! "$img_url" =~ ${SITE_URL}/ ]]; then
                    img_url="${SITE_URL}/${img_url#${SITE_URL}}"
                fi
            fi
            
            # Add image to description if available
            if [ -n "$image" ]; then
                local img_html="<p><img src=\"$img_url\" alt=\"$title\""
                if [ -n "$image_caption" ]; then
                    img_html+=" title=\"$image_caption\""
                fi
                img_html+=" /></p>"
                if [ -n "$image_caption" ]; then
                    img_html+="<p><em>$image_caption</em></p>"
                fi
                
                # Add the image HTML at the beginning of the description
                description="${img_html}${description}"
            fi
        fi

        cat >> "$rss" << EOF
    <item>
        <title>$title</title>
        <link>${SITE_URL}/${formatted_path}/</link>
        <guid>${SITE_URL}/${formatted_path}/</guid>
        <pubDate>$rss_date</pubDate>
        <description><![CDATA[${description}]]></description>
    </item>
EOF
    done

    # Close the RSS feed
    cat >> "$rss" << EOF
</channel>
</rss>
EOF

    echo -e "${GREEN}RSS feed generated!${NC}"
}

# Clean output directory
clean_output_directory() {
    if [ "$CLEAN_OUTPUT" = true ]; then
        echo -e "${YELLOW}Cleaning output directory...${NC}"
        if [ -d "$OUTPUT_DIR" ]; then
            rm -rf "${OUTPUT_DIR:?}"/*
            echo -e "${GREEN}Output directory cleaned!${NC}"
        fi
    fi
}

# Process all markdown files
process_all_markdown_files() {
    echo -e "${YELLOW}Processing markdown files...${NC}"

    local file_index="$CACHE_DIR/file_index.txt"
    
    # Check if file index exists
    if [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index not found at $file_index${NC}"
        return 1
    fi
    
    local file_count=$(wc -l < "$file_index")
    echo -e "Checking ${GREEN}$file_count${NC} markdown files for changes"

    # Define a function for processing a single file
    process_single_file() {
        local line="$1"
        local file filename title date tags slug image image_caption description
        IFS='|' read -r file filename title date tags slug image image_caption description <<< "$line"

        # Create output path based on slug format
        local output_path
        
        # Extract year, month, day from the date
        local year month day
        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
            year="${BASH_REMATCH[1]}"
            month="${BASH_REMATCH[2]}"
            day="${BASH_REMATCH[3]}"
            # Remove leading zeros before using printf
            month=$(echo "$month" | sed 's/^0*//')
            day=$(echo "$day" | sed 's/^0*//')
            # Ensure month and day have leading zeros
            month=$(printf "%02d" "$month")
            day=$(printf "%02d" "$day")
        else
            # Default to current date if date format is unrecognized
            year=$(date +%Y)
            month=$(date +%m)
            day=$(date +%d)
        fi
        
        # Apply URL_SLUG_FORMAT to create the output path
        output_path="$OUTPUT_DIR"
        
        # Replace placeholders in URL_SLUG_FORMAT
        local formatted_path="${URL_SLUG_FORMAT//Year/$year}"
        formatted_path="${formatted_path//Month/$month}"
        formatted_path="${formatted_path//Day/$day}"
        formatted_path="${formatted_path//slug/$slug}"
        
        # Create the final output path
        output_path="$OUTPUT_DIR/$formatted_path"

        # Convert markdown to HTML
        convert_markdown "$file" "$output_path" "$title" "$date" "$tags" "$slug" "$image" "$image_caption" "$description"
        
        # Create a symlink for backward compatibility if needed
        # Only create symlinks if not using Year/Month/Day/slug format
        if [ "$URL_SLUG_FORMAT" != "Year/Month/Day/slug" ] && [ ! -e "$OUTPUT_DIR/$filename.html" ]; then
            # Get the relative path in a cross-platform way
            local relative_path
            
            # Different approach for different platforms
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS doesn't have realpath with --relative-to
                # Use python to get the relative path
                if command -v python3 &> /dev/null; then
                    relative_path=$(python3 -c "import os.path; print(os.path.relpath('$output_path', '$OUTPUT_DIR'))")
                elif command -v python &> /dev/null; then
                    relative_path=$(python -c "import os.path; print(os.path.relpath('$output_path', '$OUTPUT_DIR'))")
                else
                    # Fallback to a simpler relative path calculation
                    relative_path="${formatted_path}"
                fi
            else
                # Linux and other systems with full realpath support
                relative_path=$(realpath --relative-to="$OUTPUT_DIR" "$output_path")
            fi
            
            (cd "$OUTPUT_DIR" && ln -sf "$relative_path/index.html" "$filename.html")
        fi
    }
    
    # Use GNU parallel if available, otherwise fallback to sequential processing
    if [ "$HAS_PARALLEL" = true ]; then
        echo -e "${GREEN}Using GNU parallel to process markdown files${NC}"
        # Get number of CPU cores
        local cores=1
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            cores=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        fi
        
        # First export all functions and variables needed by parallel
        export CACHE_DIR OUTPUT_DIR URL_SLUG_FORMAT PAGES_DIR CONFIG_HASH_FILE
        export FORCE_REBUILD HEADER_TEMPLATE FOOTER_TEMPLATE
        export MARKDOWN_PROCESSOR MARKDOWN_PL_PATH RED GREEN YELLOW NC
        export THEME THEMES_DIR SITE_TITLE SITE_DESCRIPTION SITE_URL
        export AUTHOR_NAME AUTHOR_EMAIL TEMPLATES_DIR DATE_FORMAT
        export -f process_single_file convert_markdown get_file_mtime format_date
        export -f extract_metadata calculate_reading_time lock_file unlock_file
        export -f format_date format_date_from_timestamp generate_slug
        export -f config_has_changed indexes_need_rebuild file_needs_rebuild
        
        # We need to make sure templates are loaded and available to all processes
        if [ -z "$HEADER_TEMPLATE" ] || [ -z "$FOOTER_TEMPLATE" ]; then
            # Check if templates are in the theme subdirectory or directly in templates dir
            if [ -f "$TEMPLATES_DIR/$THEME/header.html" ] && [ -f "$TEMPLATES_DIR/$THEME/footer.html" ]; then
                # Templates are in theme subdirectory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/footer.html")"
            elif [ -f "$TEMPLATES_DIR/header.html" ] && [ -f "$TEMPLATES_DIR/footer.html" ]; then
                # Templates are directly in templates directory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/footer.html")"
            else
                echo -e "${RED}Error: Template files not found in $TEMPLATES_DIR or $TEMPLATES_DIR/$THEME${NC}"
                return 1
            fi
        fi
        export HEADER_TEMPLATE FOOTER_TEMPLATE
        
        # Use GNU parallel to process files with a smaller number of jobs to avoid overloading
        cat "$file_index" | parallel --jobs "$cores" process_single_file
    else
        # Fallback to sequential processing
        echo -e "${YELLOW}Using sequential processing${NC}"
        cat "$file_index" | while read -r line; do
            process_single_file "$line"
        done
    fi

    echo -e "${GREEN}All markdown files processed!${NC}"
}

# Build a simple archive index by year and month
build_archive_index() {
    echo -e "${YELLOW}Building archive index...${NC}"
    
    # Check if rebuild is needed
    if ! indexes_need_rebuild && [ -f "$CACHE_DIR/archive_index.txt" ]; then
        # Check if any posts have been added (new posts not in the archive index yet)
        local current_files=$(find "$SRC_DIR" -type f -name "*.md" | wc -l)
        local indexed_files=0
        
        if [ -f "$CACHE_DIR/file_index.txt" ]; then
            indexed_files=$(wc -l < "$CACHE_DIR/file_index.txt")
        fi
        
        # If there are more current files than indexed files, we need to rebuild
        if [ "$current_files" -gt "$indexed_files" ]; then
            echo -e "${YELLOW}New posts detected, rebuilding archive index...${NC}"
        else
            echo -e "${GREEN}Archive index is up to date, skipping...${NC}"
            return
        fi
    fi
    
    local archive_index_file="$CACHE_DIR/archive_index.txt"
    
    # Get lock
    lock_file "$archive_index_file"
    
    > "$archive_index_file"  # Clear the file

    # Read from file index for efficiency
    cat "$CACHE_DIR/file_index.txt" | while read -r line; do
        local file filename title date tags slug image image_caption description
        IFS='|' read -r file filename title date tags slug image image_caption description <<< "$line"

        if [ -n "$date" ]; then
            # Extract year and month from date
            local year month
            
            # Handle different date formats
            if [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
                # Format: YYYY-MM-DD
                year=$(echo "$date" | cut -d'-' -f1)
                month=$(echo "$date" | cut -d'-' -f2)
            elif [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
                # Format: YYYY-MM-DD HH:MM:SS
                year=$(echo "$date" | cut -d'-' -f1)
                month=$(echo "$date" | cut -d'-' -f2)
            elif [[ "$date" =~ ^[A-Za-z]+\ [0-9]{1,2},\ [0-9]{4} ]]; then
                # Format: Month DD, YYYY
                month=$(echo "$date" | awk '{print $1}')
                year=$(echo "$date" | awk '{print $3}' | tr -d ',')
                # Convert month name to number
                case "${month,,}" in
                    "january"|"jan") month="01" ;;
                    "february"|"feb") month="02" ;;
                    "march"|"mar") month="03" ;;
                    "april"|"apr") month="04" ;;
                    "may") month="05" ;;
                    "june"|"jun") month="06" ;;
                    "july"|"jul") month="07" ;;
                    "august"|"aug") month="08" ;;
                    "september"|"sep") month="09" ;;
                    "october"|"oct") month="10" ;;
                    "november"|"nov") month="11" ;;
                    "december"|"dec") month="12" ;;
                esac
            else
                # Try to extract using date command for other formats
                if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
                    # BSD systems
                    if [[ -n "$DATE_FORMAT" ]]; then
                        year=$(date -j -f "$DATE_FORMAT" "$date" "+%Y" 2>/dev/null || echo "Unknown")
                        month=$(date -j -f "$DATE_FORMAT" "$date" "+%m" 2>/dev/null || echo "Unknown")
                    else
                        year=$(date -j -f "%Y-%m-%d %H:%M:%S" "$date" "+%Y" 2>/dev/null || \
                               date -j -f "%Y-%m-%d" "$date" "+%Y" 2>/dev/null || \
                               date -j -f "%b %d, %Y" "$date" "+%Y" 2>/dev/null || echo "Unknown")
                        month=$(date -j -f "%Y-%m-%d %H:%M:%S" "$date" "+%m" 2>/dev/null || \
                                date -j -f "%Y-%m-%d" "$date" "+%m" 2>/dev/null || \
                                date -j -f "%b %d, %Y" "$date" "+%m" 2>/dev/null || echo "Unknown")
                    fi
                else
                    # Linux and other Unix-like systems
                    year=$(date -d "$date" "+%Y" 2>/dev/null || echo "Unknown")
                    month=$(date -d "$date" "+%m" 2>/dev/null || echo "Unknown")
                fi
            fi

            # Skip if we couldn't parse the date
            if [ "$year" = "Unknown" ] || [ "$month" = "Unknown" ]; then
                echo -e "${YELLOW}Warning: Could not parse date from '$date' in file $file${NC}"
                continue
            fi

            # Get month name
            local month_name
            case "$month" in
                "01") month_name="January" ;;
                "02") month_name="February" ;;
                "03") month_name="March" ;;
                "04") month_name="April" ;;
                "05") month_name="May" ;;
                "06") month_name="June" ;;
                "07") month_name="July" ;;
                "08") month_name="August" ;;
                "09") month_name="September" ;;
                "10") month_name="October" ;;
                "11") month_name="November" ;;
                "12") month_name="December" ;;
                *) month_name="Unknown" ;;
            esac

            echo "$year|$month|$month_name|$title|$date|$filename.html|$slug|$image|$image_caption|$description" >> "$archive_index_file"
        fi
    done
    
    # Release lock
    unlock_file "$archive_index_file"

    echo -e "${GREEN}Archive index built!${NC}"
}

# Generate archive pages for years and months
generate_archive_pages() {
    echo -e "${YELLOW}Processing archive pages...${NC}"
    
    # Check if rebuild is needed
    if ! indexes_need_rebuild; then
        echo -e "${GREEN}Archive pages are up to date, skipping...${NC}"
        return
    fi
    
    local archive_index_file="$CACHE_DIR/archive_index.txt"
    
    # Check if the archive index file exists
    if [ ! -f "$archive_index_file" ]; then
        echo -e "${RED}Error: Archive index file not found at $archive_index_file${NC}"
        return 1
    fi

    # Create archives directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR/archives"

    # Get unique years
    local unique_years=$(awk -F'|' '{print $1}' "$archive_index_file" | sort -r | uniq)
    local year_count=$(echo "$unique_years" | wc -l)
    echo -e "Checking archive pages for ${GREEN}$year_count${NC} years"

    # Generate the main archives index page
    local archives_index="$OUTPUT_DIR/archives/index.html"

    # Generate the main archives index
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"

    # Replace placeholders in the header
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"${MSG_ARCHIVES:-"Archives"}"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}

    # Set og:type to website for archives
    header_content=${header_content//\{\{og_type\}\}/"website"}
    
    # Set proper URL in og:url
    header_content=${header_content//\{\{page_url\}\}/"archives/"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    
    # Generate CollectionPage schema for archives
    local schema_json_ld=""
    local tmp_schema=$(mktemp)
    
    # Write schema to the temporary file
    cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "Archives",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL/archives/",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
    
    # Read the schema from the temporary file
    schema_json_ld=$(cat "$tmp_schema")
    
    # Remove the temporary file
    rm "$tmp_schema"
    
    # Add schema markup to header
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

    # Remove image placeholders
    header_content=${header_content//\{\{og_image\}\}/""}
    header_content=${header_content//\{\{twitter_image\}\}/""}

    # Replace placeholders in the footer
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

    # Create the archives index page
    cat > "$archives_index" << EOF
$header_content
<h1>${MSG_ARCHIVES:-"Archives"}</h1>
<div class="archives-list">
EOF

    # Add years to the archives index
    for year in $unique_years; do
        # Count posts for this year
        local year_post_count=0
        if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
            year_post_count=$(grep -c "^$year|" "$archive_index_file" 2>/dev/null || echo 0)
        fi
        
        # Extract months for this year and count posts per month
        local months_data=$(grep "^$year|" "$archive_index_file" 2>/dev/null || echo "")
        local months=$(echo "$months_data" | awk -F'|' '{print $2}' | sort -u)
        declare -A month_counts # Redeclare array for each year

        # Populate month_counts INSIDE the for year loop
        # Use awk to count directly, then read the output
        local counts_output=$(echo "$months_data" | awk -F'|' 'NF>=2 { month_counts[$2]++ } END { for (m in month_counts) print m"|"month_counts[m] }')
        while IFS='|' read -r month_num count; do
            if [[ -n "$month_num" ]]; then
                # Use awk for safe two-digit formatting
                local formatted_month=$(awk -v m="$month_num" 'BEGIN { printf "%02d", m }')
                month_counts[$formatted_month]=$count
            fi
        done <<< "$counts_output" # Use here-string to avoid subshell

        # Display year heading with post count
        echo "<div class=\"year-group\">" >> "$archives_index"
        echo "<h2><a href=\"$(fix_url "/archives/$year/")\">$year <span class=\"post-count\">($year_post_count ${MSG_POSTS:-"posts"})</span></a></h2>" >> "$archives_index"
        echo "<ul class=\"month-list\">" >> "$archives_index"
        
        # Loop through months and generate links
        for month_idx_raw in $(echo "$months" | tr ' ' '\n' | sort -r); do
             # Format month index consistently (skip if empty)
            [[ -z "$month_idx_raw" ]] && continue
            # Use awk for safe two-digit formatting
            local month_idx=$(awk -v m="$month_idx_raw" 'BEGIN { printf "%02d", m }') # Ensure two digits
            
            # Use locale variable for month name
            local month_var_name="MSG_MONTH_$month_idx"
            # Ensure month_name has a fallback if locale variable isn't set
            local month_name=${!month_var_name:-$(LC_TIME=C date -d "$year-$month_idx-01" +'%B' 2>/dev/null || LC_TIME=C date -j -f "%Y-%m-%d" "$year-$month_idx-01" +'%B' 2>/dev/null || echo "Month $month_idx")}
            # Access month_counts with the consistently formatted index
            local month_post_count="${month_counts[$month_idx]:-0}" # Access with formatted index
            
            echo "<li><a href=\"$(fix_url "/archives/$year/$month_idx.html")\">$month_name <span class=\"post-count\">($month_post_count ${MSG_POSTS:-"posts"})</span></a></li>" >> "$archives_index"
        done

        echo "</ul>" >> "$archives_index"
        echo "</div>" >> "$archives_index"
    done

    # Close the archives index page
    cat >> "$archives_index" << EOF
</div>
$footer_content
EOF

    # Define modified file_needs_rebuild function for parallel use
    parallel_file_needs_rebuild() {
        local input_file="$1"
        local output_file="$2"

        # Skip the config_has_changed check in common_rebuild_check for parallel processes 
        # to avoid unnecessary file I/O and potential locking issues
        
        # Force rebuild if flag is set
        if [ "$FORCE_REBUILD" = true ]; then
            return 0  # Rebuild needed
        fi
        
        # Skip the config change check that would be in common_rebuild_check
        
        # Check if templates have changed
        local header_template="$TEMPLATES_DIR/header.html"
        local footer_template="$TEMPLATES_DIR/footer.html"
        
        if [ -f "$output_file" ]; then
            local input_time=$(get_file_mtime "$input_file")
            local output_time=$(get_file_mtime "$output_file")
            local header_time=$(get_file_mtime "$header_template")
            local footer_time=$(get_file_mtime "$footer_template")
            
            # Force rebuild if any template is newer than the output
            if (( header_time > output_time )) || (( footer_time > output_time )); then
                return 0  # Rebuild needed
            fi
            
            # Skip if output exists and is newer than input
            if (( output_time >= input_time )); then
                return 1  # No rebuild needed
            fi
        fi
        return 0  # Rebuild needed
    }

    # Define function to process a single year
    process_year() {
        local year="$1"
        local archive_index_file="$CACHE_DIR/archive_index.txt"
        
        # Create year directory
        mkdir -p "$OUTPUT_DIR/archives/$year"
        
        # Create year index file
        local year_index="$OUTPUT_DIR/archives/$year/index.html"
        
        local header_content="$HEADER_TEMPLATE"
        local footer_content="$FOOTER_TEMPLATE"

        # Replace placeholders in the header
        header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
        header_content=${header_content//\{\{page_title\}\}/"${MSG_ARCHIVES_FOR:-"Archives for"} $year"}
        header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}

        # Set og:type to website for archives
        header_content=${header_content//\{\{og_type\}\}/"website"}
        
        # Set proper URL in og:url
        header_content=${header_content//\{\{page_url\}\}/"archives/$year/"}
        header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
        
        # Generate CollectionPage schema for year archives
        local schema_json_ld=""
        local tmp_schema=$(mktemp)
        
        # Write schema to the temporary file
        cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "Archives for $year",
  "description": "Archive of posts from $year",
  "url": "$SITE_URL/archives/$year/",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
        
        # Read the schema from the temporary file
        schema_json_ld=$(cat "$tmp_schema")
        
        # Remove the temporary file
        rm "$tmp_schema"
        
        # Add schema markup to header
        header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

        # Remove image placeholders
        header_content=${header_content//\{\{og_image\}\}/""}
        header_content=${header_content//\{\{twitter_image\}\}/""}

        # Replace placeholders in the footer
        footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
        footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

        # Create the year index page
        cat > "$year_index" << EOF
$header_content
<h1>${MSG_ARCHIVES_FOR:-"Archives for"} $year</h1>

<div class="archives-nav">
    <a href="$(fix_url "/archives/")">← ${MSG_BACK_TO:-"Back to"} ${MSG_ARCHIVES:-"Archives"} Index</a>
</div>

<div class="month-list">
EOF

        # Get unique months for this year
        local unique_months=""
        if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
            unique_months=$(grep "^$year|" "$archive_index_file" 2>/dev/null | awk -F'|' '{print $2 "|" $3}' | sort | uniq)
        fi
        local month_count=$(echo "$unique_months" | grep -v '^$' | wc -l)
        
        # Add months to the year page
        echo "$unique_months" | while read -r month_line; do
            local month month_name
            IFS='|' read -r month month_name <<< "$month_line"
            
            if [ -n "$month" ] && [ -n "$month_name" ]; then
                # Count posts for this month
                local month_post_count=0
                if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
                    month_post_count=$(grep -c "^$year|$month|" "$archive_index_file" 2>/dev/null || echo 0)
                fi
                
                # Use locale variable for month name
                # Format month with awk BEFORE building var name
                local month_idx_formatted=$(awk -v m="$month" 'BEGIN { printf "%02d", m }')
                # Use the already formatted month index
                local month_var_name="MSG_MONTH_$month_idx_formatted"
                local current_month_name=${!month_var_name:-$month_name} # Use original month_name as fallback
                
                cat >> "$year_index" << EOF
    <h2><a href="${SITE_URL}/archives/$year/$month.html">$current_month_name <span class="post-count">($month_post_count ${MSG_POSTS:-"posts"})</span></a></h2>
EOF

                # Process this month - pass the potentially translated month name
                # Pass the original (non-formatted) month number
                process_month "$year" "$month" "$current_month_name"
            fi
        done

        cat >> "$year_index" << EOF
</div>
$footer_content
EOF
        echo -e "Generated archive page for year: ${GREEN}$year${NC}"
    }
    
    # Define function to process a single month
    process_month() {
        local year="$1"
        local month="$2"
        local month_name="$3" # This is now the potentially translated name
        local archive_index_file="$CACHE_DIR/archive_index.txt"
        
        # Create month page
        local month_file="$OUTPUT_DIR/archives/$year/$month.html"
                
        local month_header_content="$HEADER_TEMPLATE"
        local month_footer_content="$FOOTER_TEMPLATE"

        # Replace placeholders in the header
        month_header_content=${month_header_content//\{\{site_title\}\}/"$SITE_TITLE"}
        month_header_content=${month_header_content//\{\{page_title\}\}/"${MSG_POSTS_FROM:-"Posts from"} $month_name $year"}
        month_header_content=${month_header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        month_header_content=${month_header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        month_header_content=${month_header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}

        # Set og:type to website for archives
        month_header_content=${month_header_content//\{\{og_type\}\}/"website"}
        
        # Set proper URL in og:url
        month_header_content=${month_header_content//\{\{page_url\}\}/"archives/$year/$month.html"}
        month_header_content=${month_header_content//\{\{site_url\}\}/"$SITE_URL"}
        
        # Generate CollectionPage schema for month archives
        local schema_json_ld=""
        local tmp_schema=$(mktemp)
        
        # Write schema to the temporary file
        cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "Archives for $month_name $year",
  "description": "Archive of posts from $month_name $year",
  "url": "$SITE_URL/archives/$year/$month.html",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
        
        # Read the schema from the temporary file
        schema_json_ld=$(cat "$tmp_schema")
        
        # Remove the temporary file
        rm "$tmp_schema"
        
        # Add schema markup to header
        month_header_content=${month_header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

        # Remove image placeholders
        month_header_content=${month_header_content//\{\{og_image\}\}/""}
        month_header_content=${month_header_content//\{\{twitter_image\}\}/""}

        # Replace placeholders in the footer
        month_footer_content=${month_footer_content//\{\{current_year\}\}/$(date +%Y)}
        month_footer_content=${month_footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

        # Create the month page
        mkdir -p "$(dirname "$month_file")"
        cat > "$month_file" << EOF
$month_header_content
<h1>${MSG_POSTS_FROM:-"Posts from"} $month_name $year</h1>

<div class="archives-nav">
    <a href="$(fix_url "/archives/$year/")">← ${MSG_BACK_TO:-"Back to"} $year ${MSG_ARCHIVES:-"Archives"}</a>
</div>

<div class="posts-list">
EOF

        # Add posts for this month
        if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
            grep "^$year|$month|" "$archive_index_file" 2>/dev/null | sort -t'|' -k5 || true
        fi | while read -r post_line; do
            if [ -z "$post_line" ]; then
                continue
            fi
            
            local _ _ _ title date filename slug image image_caption description
            IFS='|' read -r _ _ _ title date filename slug image image_caption description <<< "$post_line"
            
            # Create slug-based URL path according to URL_SLUG_FORMAT
            # Extract year, month, day from the date
            local post_year post_month post_day
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                post_year="${BASH_REMATCH[1]}"
                post_month="${BASH_REMATCH[2]}"
                post_day="${BASH_REMATCH[3]}"
                # Remove leading zeros before using printf/awk
                post_month=$(echo "$post_month" | sed 's/^0*//')
                post_day=$(echo "$post_day" | sed 's/^0*//')
                # Ensure month and day have leading zeros using awk
                post_month=$(awk -v m="$post_month" 'BEGIN { printf "%02d", m }')
                post_day=$(awk -v d="$post_day" 'BEGIN { printf "%02d", d }')
            else
                # Default to current date if date format is unrecognized
                post_year=$(date +%Y)
                post_month=$(date +%m)
                post_day=$(date +%d)
            fi
            
            # Apply URL_SLUG_FORMAT to create the URL path
            local formatted_path="${URL_SLUG_FORMAT//Year/$post_year}"
            formatted_path="${formatted_path//Month/$post_month}"
            formatted_path="${formatted_path//Day/$post_day}"
            formatted_path="${formatted_path//slug/$slug}"

            cat >> "$month_file" << EOF
    <article>
        <h3><a href="${SITE_URL}/$formatted_path/">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $(format_date "$date")${AUTHOR_NAME:+" ${MSG_BY:-"by"} $AUTHOR_NAME"}</div>
EOF

            # Add featured image if specified
            if [ -n "$image" ]; then
                # Process image URL to add SITE_URL if it's a relative path
                local image_url="$image"
                if [[ "$image" == /* ]]; then
                    image_url="${SITE_URL}${image}"
                fi

                cat >> "$month_file" << EOF
        <div class="featured-image">
            <a href="${SITE_URL}/$formatted_path/">
                <img src="$image_url" alt="${title}" />
                ${image_caption:+<div class="image-caption">$image_caption</div>}
            </a>
        </div>
EOF
            fi

            # Add description if specified
            if [ -n "$description" ]; then
                cat >> "$month_file" << EOF
        <div class="description">
            $description
        </div>
EOF
            fi

            cat >> "$month_file" << EOF
        <div class="read-more">
            <a href="${SITE_URL}/$formatted_path/">${MSG_READ_MORE:-"Read more"} →</a>
        </div>
    </article>
EOF
        done

        # Close the month page
        cat >> "$month_file" << EOF
</div>
$month_footer_content
EOF
        echo -e "Generated archive page for month: ${GREEN}$month_name $year${NC}"
    }

    # Use GNU parallel if available, otherwise fallback to sequential processing
    if [ "$HAS_PARALLEL" = true ]; then
        echo -e "${GREEN}Using GNU parallel to process archive pages${NC}"
        # Get number of CPU cores
        local cores=1
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            cores=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        fi
        
        # Export required functions and variables
        export CACHE_DIR OUTPUT_DIR URL_SLUG_FORMAT CONFIG_HASH_FILE
        export HEADER_TEMPLATE FOOTER_TEMPLATE FORCE_REBUILD
        export SITE_TITLE SITE_DESCRIPTION SITE_URL TEMPLATES_DIR DATE_FORMAT
        export AUTHOR_NAME
        export -f process_year process_month format_date get_file_mtime fix_url
        export -f parallel_file_needs_rebuild
        
        # We need to make sure templates are loaded and available to all processes
        if [ -z "$HEADER_TEMPLATE" ] || [ -z "$FOOTER_TEMPLATE" ]; then
            # Check if templates are in the theme subdirectory or directly in templates dir
            if [ -f "$TEMPLATES_DIR/$THEME/header.html" ] && [ -f "$TEMPLATES_DIR/$THEME/footer.html" ]; then
                # Templates are in theme subdirectory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/footer.html")"
            elif [ -f "$TEMPLATES_DIR/header.html" ] && [ -f "$TEMPLATES_DIR/footer.html" ]; then
                # Templates are directly in templates directory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/footer.html")"
            else
                echo -e "${RED}Error: Template files not found in $TEMPLATES_DIR or $TEMPLATES_DIR/$THEME${NC}"
                return 1
            fi
        fi
        export HEADER_TEMPLATE FOOTER_TEMPLATE
        
        # Use GNU parallel to process years with a smaller number of jobs to avoid overloading
        echo "$unique_years" | parallel --jobs "$cores" process_year
    else
        # Sequential processing
        echo -e "${YELLOW}Using sequential processing${NC}"
        for year in $unique_years; do
            process_year "$year"
        done
    fi
    
    echo -e "${GREEN}Archive pages generated!${NC}"
}

# Generate tag pages
generate_tag_pages() {
    echo -e "${YELLOW}Processing tag pages...${NC}"

    local tags_index_file="$CACHE_DIR/tags_index.txt"
    
    # Check if the tags index file exists
    if [ ! -f "$tags_index_file" ]; then
        echo -e "${RED}Error: Tags index file not found at $tags_index_file${NC}"
        return 1
    fi

    # Get unique tags
    local unique_tags=$(awk -F'|' '{print $1 "|" $2}' "$tags_index_file" | sort | uniq)
    local tag_count=$(echo "$unique_tags" | grep -v '^$' | wc -l)
    echo -e "Checking ${GREEN}$tag_count${NC} tag pages for changes"

    # Define a modified file_needs_rebuild function for parallel use
    parallel_file_needs_rebuild() {
        local input_file="$1"
        local output_file="$2"

        # Skip the config_has_changed check in common_rebuild_check for parallel processes 
        # to avoid unnecessary file I/O and potential locking issues
        
        # Force rebuild if flag is set
        if [ "$FORCE_REBUILD" = true ]; then
            return 0  # Rebuild needed
        fi
        
        # Skip the config change check that would be in common_rebuild_check
        
        # Check if templates have changed
        local header_template="$TEMPLATES_DIR/header.html"
        local footer_template="$TEMPLATES_DIR/footer.html"
        
        if [ -f "$output_file" ]; then
            local input_time=$(get_file_mtime "$input_file")
            local output_time=$(get_file_mtime "$output_file")
            local header_time=$(get_file_mtime "$header_template")
            local footer_time=$(get_file_mtime "$footer_template")
            
            # Force rebuild if any template is newer than the output
            if (( header_time > output_time )) || (( footer_time > output_time )); then
                return 0  # Rebuild needed
            fi
            
            # Skip if output exists and is newer than input
            if (( output_time >= input_time )); then
                return 1  # No rebuild needed
            fi
        fi
        return 0  # Rebuild needed
    }

    # Define a function to process a single tag
    process_tag() {
        local tag_line="$1"
        local tags_index_file="$2"
        local tag tag_url
        IFS='|' read -r tag tag_url <<< "$tag_line"

        if [ -n "$tag" ]; then
            local tag_file="$OUTPUT_DIR/tags/$tag_url.html"

            # Skip if tag page is up to date
            if ! parallel_file_needs_rebuild "$tags_index_file" "$tag_file"; then
                echo -e "Skipping unchanged tag: ${YELLOW}$tag${NC}"
                return 0
            fi

            local header_content="$HEADER_TEMPLATE"
            local footer_content="$FOOTER_TEMPLATE"

            # Replace placeholders in the header
            header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
            # Use MSG_ variable for page title
            header_content=${header_content//\{\{page_title\}\}/"${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag"}
            header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
            header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
            header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}

            # Set website og:type for tag pages
            header_content=${header_content//\{\{og_type\}\}/"website"}
            
            # Set proper URL in og:url
            header_content=${header_content//\{\{page_url\}\}/"tags/$tag_url.html"}
            header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
            
            # Generate CollectionPage schema for tag pages
            local schema_json_ld=""
            local tmp_schema=$(mktemp)
            
            # Write the schema to the temporary file
            cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "Posts tagged with: $tag",
  "description": "Posts with tag: $tag",
  "url": "$SITE_URL/tags/$tag_url.html",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
            
            # Read the schema from the temporary file
            schema_json_ld=$(cat "$tmp_schema")
            
            # Remove the temporary file
            rm "$tmp_schema"
            
            # Add schema markup to header
            header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

            # Remove image placeholders
            header_content=${header_content//\{\{og_image\}\}/""}
            header_content=${header_content//\{\{twitter_image\}\}/""}

            # Replace placeholders in the footer
            footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
            footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

            # Create the tag page
            mkdir -p "$(dirname "$tag_file")"
            cat > "$tag_file" << EOF
$header_content
<h1>${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag</h1>
<div class="posts-list">
EOF

            # Add posts for this tag - use direct approach for parallel safety
            # Create a temporary file with all tag entries
            local temp_file=$(mktemp)
            
            # Extract entries for this tag safely
            awk -F'|' -v tag="$tag" -v url="$tag_url" '$1 == tag && $2 == url' "$tags_index_file" > "$temp_file"
            
            # Process each entry
            if [ -s "$temp_file" ]; then  # Check if file has content
                while IFS= read -r post_line; do
                    if [ -z "$post_line" ]; then
                        continue
                    fi
                    
                    local _ _ title date filename slug image image_caption description
                    IFS='|' read -r _ _ title date filename slug image image_caption description <<< "$post_line"
                    
                    # Create slug-based URL path according to URL_SLUG_FORMAT
                    # Extract year, month, day from the date
                    local post_year post_month post_day
                    if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                        post_year="${BASH_REMATCH[1]}"
                        post_month="${BASH_REMATCH[2]}"
                        post_day="${BASH_REMATCH[3]}"
                        # Remove leading zeros before using printf/awk
                        post_month=$(echo "$post_month" | sed 's/^0*//')
                        post_day=$(echo "$post_day" | sed 's/^0*//')
                        # Ensure month and day have leading zeros using awk
                        post_month=$(awk -v m="$post_month" 'BEGIN { printf "%02d", m }')
                        post_day=$(awk -v d="$post_day" 'BEGIN { printf "%02d", d }')
                    else
                        # Default to current date if date format is unrecognized
                        post_year=$(date +%Y)
                        post_month=$(date +%m)
                        post_day=$(date +%d)
                    fi
                    
                    # Apply URL_SLUG_FORMAT to create the URL path
                    local formatted_path="${URL_SLUG_FORMAT//Year/$post_year}"
                    formatted_path="${formatted_path//Month/$post_month}"
                    formatted_path="${formatted_path//Day/$post_day}"
                    formatted_path="${formatted_path//slug/$slug}"

                    cat >> "$tag_file" << EOF
    <article>
        <h3><a href="${SITE_URL}/$formatted_path/">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $(format_date "$date")</div>
EOF

                    # Add featured image if specified
                    if [ -n "$image" ]; then
                        # Process image URL to add SITE_URL if it's a relative path
                        local image_url="$image"
                        if [[ "$image" == /* ]]; then
                            image_url="${SITE_URL}${image}"
                        fi
                        
                        cat >> "$tag_file" << EOF
        <div class="featured-image tag-image">
            <a href="${SITE_URL}/$formatted_path/">
                <img src="$image_url" alt="${title}" />
                ${image_caption:+<div class="image-caption">$image_caption</div>}
            </a>
        </div>
EOF
                    fi
                    
                    
                    # Add description/excerpt if available
                    if [ -n "$description" ]; then
                        cat >> "$tag_file" << EOF
        <div class="summary">
            <p>$description</p>
        </div>
EOF
                    fi

                    cat >> "$tag_file" << EOF
    </article>
EOF
                done < "$temp_file"
            fi

            # Close the tag page
            cat >> "$tag_file" << EOF
</div>
<p><a href="${SITE_URL}/tags/">${MSG_ALL_TAGS:-"All Tags"}</a></p>
$footer_content
EOF
            echo -e "Generated tag page for: ${GREEN}$tag${NC}"
        fi
    }

    # Use GNU parallel if available, otherwise fallback to sequential processing
    if [ "$HAS_PARALLEL" = true ]; then
        echo -e "${GREEN}Using GNU parallel to process tag pages${NC}"
        # Get number of CPU cores
        local cores=1
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            cores=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        fi
        
        # Export required functions and variables
        export CACHE_DIR OUTPUT_DIR URL_SLUG_FORMAT CONFIG_HASH_FILE
        export HEADER_TEMPLATE FOOTER_TEMPLATE FORCE_REBUILD
        export SITE_TITLE SITE_DESCRIPTION SITE_URL TEMPLATES_DIR DATE_FORMAT
        export AUTHOR_NAME
        export -f process_tag parallel_file_needs_rebuild format_date get_file_mtime fix_url
        
        # We need to make sure templates are loaded and available to all processes
        if [ -z "$HEADER_TEMPLATE" ] || [ -z "$FOOTER_TEMPLATE" ]; then
            # Check if templates are in the theme subdirectory or directly in templates dir
            if [ -f "$TEMPLATES_DIR/$THEME/header.html" ] && [ -f "$TEMPLATES_DIR/$THEME/footer.html" ]; then
                # Templates are in theme subdirectory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/footer.html")"
            elif [ -f "$TEMPLATES_DIR/header.html" ] && [ -f "$TEMPLATES_DIR/footer.html" ]; then
                # Templates are directly in templates directory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/footer.html")"
            else
                echo -e "${RED}Error: Template files not found in $TEMPLATES_DIR or $TEMPLATES_DIR/$THEME${NC}"
                return 1
            fi
        fi
        export HEADER_TEMPLATE FOOTER_TEMPLATE
        
        # Use GNU parallel to process tags with a smaller number of jobs to avoid overloading
        echo "$unique_tags" | grep -v '^$' | parallel --jobs "$cores" process_tag {} "$tags_index_file"
    else
        # Sequential processing
        echo -e "${YELLOW}Using sequential processing${NC}"
        echo "$unique_tags" | while read -r tag_line; do
            process_tag "$tag_line" "$tags_index_file"
        done
    fi

    # Generate tags index page
    local tags_index="$OUTPUT_DIR/tags/index.html"

    # Skip if tag index is up to date
    if ! file_needs_rebuild "$tags_index_file" "$tags_index"; then
        echo -e "Skipping unchanged tags index"
    else
        local header_content="$HEADER_TEMPLATE"
        local footer_content="$FOOTER_TEMPLATE"

        # Replace placeholders in the header
        header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
        header_content=${header_content//\{\{page_title\}\}/"All Tags"}
        header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
        
        # Set og:type to website for tags index
        header_content=${header_content//\{\{og_type\}\}/"website"}
        
        # Set proper URL in og:url
        header_content=${header_content//\{\{page_url\}\}/"tags/"}
        header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
        
        # Generate CollectionPage schema for tags index
        local schema_json_ld=""
        local tmp_schema=$(mktemp)
        
        # Write schema to the temporary file
        cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "All Tags",
  "description": "List of all tags on $SITE_TITLE",
  "url": "$SITE_URL/tags/",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
        
        # Read the schema from the temporary file
        schema_json_ld=$(cat "$tmp_schema")
        
        # Remove the temporary file
        rm "$tmp_schema"
        
        # Add schema markup to header
        header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}
        
        # Remove image placeholders
        header_content=${header_content//\{\{og_image\}\}/""}
        header_content=${header_content//\{\{twitter_image\}\}/""}

        # Replace placeholders in the footer
        footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
        footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

        # Create the tags index page
        mkdir -p "$(dirname "$tags_index")"
        cat > "$tags_index" << EOF
$header_content
<h1>${MSG_ALL_TAGS:-"All Tags"}</h1>
<div class="tags-list">
EOF

        # Add all tags to the index page - prevent grep errors with empty files
        echo "$unique_tags" | while read -r tag_line; do
            local tag tag_url
            IFS='|' read -r tag tag_url <<< "$tag_line"

            if [ -n "$tag" ]; then
                # Count posts with this tag, but prevent errors with empty files
                local post_count=0
                if [ -f "$tags_index_file" ] && [ -s "$tags_index_file" ]; then
                    post_count=$(grep -c "^$tag|$tag_url|" "$tags_index_file" 2>/dev/null || echo 0)
                fi

                cat >> "$tags_index" << EOF
    <a href="${SITE_URL}/tags/$tag_url.html">$tag <span class="tag-count">($post_count)</span></a>
EOF
            fi
        done

        # Close the tags index page
        cat >> "$tags_index" << EOF
</div>
$footer_content
EOF
    fi

    echo -e "${GREEN}Tag pages processed!${NC}"
}

# Generate main index page (homepage)
generate_index() {
    echo -e "${YELLOW}Generating index pages...${NC}"
    
    # Check if rebuild is needed
    if ! indexes_need_rebuild; then
        echo -e "${GREEN}Index pages are up to date, skipping...${NC}"
        return
    fi
    
    # Define the index page paths
    local file_index="$CACHE_DIR/file_index.txt"
    
    # Count total posts
    local total_posts=$(wc -l < "$file_index")
    local total_pages=$(( (total_posts + POSTS_PER_PAGE - 1) / POSTS_PER_PAGE ))
    
    echo -e "Generating ${GREEN}$total_pages${NC} index pages for ${GREEN}$total_posts${NC} posts"
    
    # Prepare templates
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"
    
    # Define function to process a single index page
    process_index_page() {
        local current_page="$1"
        local total_pages="$2"
        local file_index="$3"
        local header_content_param="$4"
        local footer_content_param="$5"
        
        # Use parameters if provided, otherwise use global variables
        local header_content=${header_content_param:-$HEADER_TEMPLATE}
        local footer_content=${footer_content_param:-$FOOTER_TEMPLATE}
        
        local output_file
        if [ $current_page -eq 1 ]; then
            output_file="$OUTPUT_DIR/index.html"
        else
            output_file="$OUTPUT_DIR/page/$current_page/index.html"
            mkdir -p "$(dirname "$output_file")"
        fi
        
        # Skip if index is up to date
        if [ "$FORCE_REBUILD" = false ] && [ -f "$output_file" ] && [ -f "$file_index" ]; then
            local index_mtime=$(get_file_mtime "$output_file")
            local file_index_mtime=$(get_file_mtime "$file_index")
            
            if (( index_mtime > file_index_mtime )); then
                echo -e "Skipping unchanged index page $current_page"
                return
            fi
        fi
        
        # Replace placeholders in the header
        local page_header="$header_content"
        page_header=${page_header//\{\{site_title\}\}/"$SITE_TITLE"}
        if [ $current_page -eq 1 ]; then
            # For the homepage, just use the site title without duplication
            page_header=${page_header//\{\{page_title\}\}/"Home"}
            
            # Set og:type to website
            page_header=${page_header//\{\{og_type\}\}/"website"}
            
            # Set proper canonical URL for homepage (just root domain)
            page_header=${page_header//\{\{page_url\}\}/""}
            
            # Ensure site_url is properly replaced
            page_header=${page_header//\{\{site_url\}\}/"$SITE_URL"}
            
            # Create WebSite schema for homepage
            local schema_json_ld=""
            local tmp_schema=$(mktemp)
            
            # Write the schema to the temporary file
            cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "name": "$SITE_TITLE",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL",
  "potentialAction": {
    "@type": "SearchAction",
    "target": "$SITE_URL/search?q={search_term_string}",
    "query-input": "required name=search_term_string"
  },
  "publisher": {
    "@type": "Organization",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
            
            # Read the schema from the temporary file
            schema_json_ld=$(cat "$tmp_schema")
            
            # Remove the temporary file
            rm "$tmp_schema"
            
            # Add schema markup to header
            page_header=${page_header//\{\{schema_json_ld\}\}/"$schema_json_ld"}
        else
            # For pagination pages
            page_header=${page_header//\{\{page_title\}\}/"$SITE_TITLE - Page $current_page"}
            
            # Set og:type to website for index pages
            page_header=${page_header//\{\{og_type\}\}/"website"}
            
            # Set canonical URL for paginated pages
            page_header=${page_header//\{\{page_url\}\}/"page/$current_page/"}
            
            # Ensure site_url is properly replaced
            page_header=${page_header//\{\{site_url\}\}/"$SITE_URL"}
            
            # Create CollectionPage schema for paginated pages
            local schema_json_ld=""
            local tmp_schema=$(mktemp)
            
            # Write the schema to the temporary file
            cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "$SITE_TITLE - Page $current_page",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL/page/$current_page/",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
            
            # Read the schema from the temporary file
            schema_json_ld=$(cat "$tmp_schema")
            
            # Remove the temporary file
            rm "$tmp_schema"
            
            # Add schema markup to header
            page_header=${page_header//\{\{schema_json_ld\}\}/"$schema_json_ld"}
        fi
        page_header=${page_header//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
        
        # Remove og_image and twitter_image placeholders if not used
        page_header=${page_header//\{\{og_image\}\}/""}
        page_header=${page_header//\{\{twitter_image\}\}/""}
        
        # Replace placeholders in the footer
        local page_footer="$footer_content"
        page_footer=${page_footer//\{\{current_year\}\}/$(date +%Y)}
        page_footer=${page_footer//\{\{author_name\}\}/"$AUTHOR_NAME"}
        
        # Create the index page
        cat > "$output_file" << EOF
$page_header
<h1>${MSG_LATEST_POSTS:-"Latest Posts"}</h1>
<div class="posts-list">
EOF
        
        # Calculate start and end indices for this page
        local start_index=$(( (current_page - 1) * POSTS_PER_PAGE + 1 ))
        local end_index=$(( current_page * POSTS_PER_PAGE ))
        
        # Add posts to the index page
        local count=0
        local current_date=""
        
        # Process files from file_index, ordered by date (newest first)
        cat "$file_index" | sort -t'|' -k4,4r | while read -r line; do
            count=$((count + 1))
            
            # Skip lines before start_index
            if [ $count -lt $start_index ]; then
                continue
            fi
            
            # Stop after end_index
            if [ $count -gt $end_index ]; then
                break
            fi
            
            # Split the line into fields
            local file filename title date tags slug image image_caption description
            IFS='|' read -r file filename title date tags slug image image_caption description <<< "$line"
            
            # Skip if any essential field is empty
            if [ -z "$file" ] || [ -z "$title" ] || [ -z "$date" ]; then
                continue
            fi
            
            # Extract year, month, day from the date
            local year month day
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month="${BASH_REMATCH[2]}"
                day="${BASH_REMATCH[3]}"
                # Remove leading zeros before using printf
                month=$(echo "$month" | sed 's/^0*//')
                day=$(echo "$day" | sed 's/^0*//')
                # Ensure month and day have leading zeros
                month=$(printf "%02d" "$month")
                day=$(printf "%02d" "$day")
            else
                # Default to current date if date format is unrecognized
                year=$(date +%Y)
                month=$(date +%m)
                day=$(date +%d)
            fi
            
            # Apply URL_SLUG_FORMAT to create the URL path
            local formatted_path="${URL_SLUG_FORMAT//Year/$year}"
            formatted_path="${formatted_path//Month/$month}"
            formatted_path="${formatted_path//Day/$day}"
            formatted_path="${formatted_path//slug/$slug}"
            
            # Format date according to settings
            local formatted_date=$(format_date "$date")
            
            # Add post to index
            cat >> "$output_file" << EOF
    <article>
        <h3><a href="${SITE_URL}/$formatted_path/">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $formatted_date${AUTHOR_NAME:+" ${MSG_BY:-"by"} $AUTHOR_NAME"}</div>
EOF

            # Add featured image if specified
            if [ -n "$image" ]; then
                cat >> "$output_file" << EOF
        <div class="featured-image index-image">
            <a href="${SITE_URL}/$formatted_path/">
                <img src="$image" alt="${title}" />
            </a>
        </div>
EOF
            fi
            
            # Add description if available
            if [ -n "$description" ]; then
                cat >> "$output_file" << EOF
        <div class="summary">
            <p>$description</p>
        </div>
EOF
            fi
            
            # Add tags if present
            if [ -n "$tags" ]; then
                cat >> "$output_file" << EOF
<div class="tags">
EOF
                IFS=',' read -ra TAG_ARRAY <<< "$tags"
                for tag in "${TAG_ARRAY[@]}"; do
                    # Remove leading/trailing whitespace
                    tag=$(echo "$tag" | sed 's/^ *//;s/ *$//')
                    # Convert to lowercase and replace spaces with hyphens for the URL
                    local tag_slug=$(generate_slug "$tag")
                    echo "            <a href=\"/tags/$tag_slug.html\" class=\"tag\">$tag</a>" >> "$output_file"
                done
                cat >> "$output_file" << EOF
</div>
EOF
            fi
            
            cat >> "$output_file" << EOF
    </article>
EOF
        done
        
        
        # Close the posts list
        cat >> "$output_file" << EOF
</div>

<!-- Pagination -->
<div class="pagination">
EOF
        
        # Add pagination links
        if [ $current_page -gt 1 ]; then
            local prev_page=$((current_page - 1))
            if [ $prev_page -eq 1 ]; then
                echo "    <a href=\"/\" class=\"prev\">&laquo; ${MSG_OLDER_POSTS:-Previous}</a>" >> "$output_file"
            else
                echo "    <a href=\"/page/$prev_page/\" class=\"prev\">&laquo; ${MSG_OLDER_POSTS:-Previous}</a>" >> "$output_file"
            fi
        fi
        
        # Add page info element (Page X of Y) only if there are multiple pages
        if [ $total_pages -gt 1 ]; then
            echo "    <span class=\"page-info\">$(printf "${MSG_PAGE_INFO_TEMPLATE:-Page %d of %d}" "$current_page" "$total_pages")</span>" >> "$output_file"
        fi
        
        if [ $current_page -lt $total_pages ]; then
            local next_page=$((current_page + 1))
            echo "    <a href=\"/page/$next_page/\" class=\"next\">${MSG_NEWER_POSTS:-Next} &raquo;</a>" >> "$output_file"
        fi
        
        # Close pagination and add footer
        cat >> "$output_file" << EOF
</div>
$page_footer
EOF
    }
    
    # Use GNU parallel if available, otherwise fallback to sequential processing
    if [ "$HAS_PARALLEL" = true ] && [ $total_pages -gt 2 ]; then
        echo -e "${GREEN}Using GNU parallel to process index pages${NC}"
        # Get number of CPU cores
        local cores=1
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            cores=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        fi
        
        # Use at most cores/2 jobs for generating index pages to avoid contention
        local jobs=$(( cores > 1 ? cores / 2 : 1 ))
        
        # Export required functions and variables
        export OUTPUT_DIR URL_SLUG_FORMAT POSTS_PER_PAGE
        export SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME DATE_FORMAT
        export FORCE_REBUILD MARKDOWN_PROCESSOR MARKDOWN_PL_PATH
        
        # Make sure templates are exported for parallel processing
        export HEADER_TEMPLATE="$header_content"
        export FOOTER_TEMPLATE="$footer_content"
        
        # Export functions needed
        export -f process_index_page get_file_mtime format_date generate_slug
        
        # Create a sequence of page numbers and process them in parallel
        seq 1 $total_pages | parallel --jobs $jobs process_index_page {} $total_pages "$file_index"
    else
        # Original sequential implementation
        local current_page=1
        while [ $current_page -le $total_pages ]; do
            process_index_page $current_page $total_pages "$file_index" "$header_content" "$footer_content"
            current_page=$((current_page + 1))
        done
    fi
    
    echo -e "${GREEN}Index pages processed!${NC}"
}

# Process all pages
process_all_pages() {
    echo -e "${YELLOW}Processing pages...${NC}"

    # Check if pages directory exists
    if [ ! -d "$PAGES_DIR" ]; then
        echo -e "${YELLOW}Pages directory not found, skipping page processing${NC}"
        return 0
    fi

    # Find all markdown and HTML files in the pages directory
    local page_files
    page_files=($(find "$PAGES_DIR" -type f \( -name "*.md" -o -name "*.html" \) | sort))

    echo -e "Checking ${GREEN}${#page_files[@]}${NC} pages for changes"
    
    # Define a function for processing a single page
    process_single_page() {
        local file="$1"
        
        # Skip if file is hidden
        if [[ $(basename "$file") == .* ]]; then
            return
        fi

        # Extract metadata from file
        local title date slug
        if [[ "$file" == *.html ]]; then
            # Extract from HTML meta tags
            title=$(grep -m 1 '<title>' "$file" | sed 's/<[^>]*>//g')
            date=$(grep -m 1 'meta name="date"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
            slug=$(grep -m 1 'meta name="slug"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
        else
            # Extract from markdown frontmatter
            title=$(parse_metadata "$file" "title")
            date=$(parse_metadata "$file" "date")
            slug=$(parse_metadata "$file" "slug")
        fi

        # If no slug is specified, generate from filename
        if [ -z "$slug" ]; then
            slug=$(basename "$file" | sed 's/\.[^.]*$//')
        fi

        # Create output path based on PAGE_URL_FORMAT
        local formatted_path="${PAGE_URL_FORMAT//slug/$slug}"
        local output_path="$OUTPUT_DIR/$formatted_path"

        # Convert page to HTML
        convert_page "$file" "$output_path" "$title" "$date" "$slug"
    }
    
    # Use GNU parallel if available, otherwise fallback to sequential processing
    if [ "$HAS_PARALLEL" = true ]; then
        echo -e "${GREEN}Using GNU parallel to process pages${NC}"
        # Get number of CPU cores
        local cores=1
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            cores=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        fi
        
        # First export all functions and variables needed by parallel
        export CACHE_DIR OUTPUT_DIR URL_SLUG_FORMAT PAGE_URL_FORMAT PAGES_DIR CONFIG_HASH_FILE
        export FORCE_REBUILD HEADER_TEMPLATE FOOTER_TEMPLATE
        export MARKDOWN_PROCESSOR MARKDOWN_PL_PATH RED GREEN YELLOW NC
        export THEME THEMES_DIR SITE_TITLE SITE_DESCRIPTION SITE_URL
        export AUTHOR_NAME AUTHOR_EMAIL TEMPLATES_DIR DATE_FORMAT
        export -f process_single_page convert_page get_file_mtime parse_metadata
        export -f extract_metadata calculate_reading_time lock_file unlock_file
        export -f format_date format_date_from_timestamp generate_slug
        export -f config_has_changed indexes_need_rebuild file_needs_rebuild
        
        # We need to make sure templates are loaded and available to all processes
        if [ -z "$HEADER_TEMPLATE" ] || [ -z "$FOOTER_TEMPLATE" ]; then
            # Check if templates are in the theme subdirectory or directly in templates dir
            if [ -f "$TEMPLATES_DIR/$THEME/header.html" ] && [ -f "$TEMPLATES_DIR/$THEME/footer.html" ]; then
                # Templates are in theme subdirectory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/$THEME/footer.html")"
            elif [ -f "$TEMPLATES_DIR/header.html" ] && [ -f "$TEMPLATES_DIR/footer.html" ]; then
                # Templates are directly in templates directory
                HEADER_TEMPLATE="$(<"$TEMPLATES_DIR/header.html")"
                FOOTER_TEMPLATE="$(<"$TEMPLATES_DIR/footer.html")"
            else
                echo -e "${RED}Error: Template files not found in $TEMPLATES_DIR or $TEMPLATES_DIR/$THEME${NC}"
                return 1
            fi
        fi
        export HEADER_TEMPLATE FOOTER_TEMPLATE
        
        # Use GNU parallel to process pages with a smaller number of jobs to avoid overloading
        printf "%s\n" "${page_files[@]}" | parallel --jobs "$cores" process_single_page
    else
        # Fallback to sequential processing
        echo -e "${YELLOW}Using sequential processing${NC}"
        for file in "${page_files[@]}"; do
            process_single_page "$file"
        done
    fi

    echo -e "${GREEN}All pages processed!${NC}"
}

# Convert a page to HTML
convert_page() {
    local input_file="$1"
    local output_base_path="$2"
    local title="$3"
    local date="$4"
    local slug="$5"

    # Check if the source file exists
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: Source file '$input_file' not found${NC}"
        return 1
    fi

    # Skip if output file is newer than input file and no force rebuild
    if [ "$FORCE_REBUILD" = false ] && [ -f "$output_base_path/index.html" ]; then
        local src_mtime=$(get_file_mtime "$input_file")
        local out_mtime=$(get_file_mtime "$output_base_path/index.html")

        if [ "$out_mtime" -ge "$src_mtime" ]; then
            echo -e "Skipping unchanged page: ${YELLOW}$(basename "$input_file")${NC}"
            return 0
        fi
    fi

    # Extract content from source file
    local content
    local html_content
    if [[ "$input_file" == *.html ]]; then
        # For HTML files, extract content between <body> tags
        html_content=$(sed -n '/<body>/,/<\/body>/p' "$input_file" | sed '1d;$d')
    else
        # For markdown files, extract content after frontmatter
        local start_line=$(grep -n "^---$" "$input_file" | head -1 | cut -d: -f1)
        local end_line=$(grep -n "^---$" "$input_file" | head -2 | tail -1 | cut -d: -f1)

        if [ -z "$start_line" ] || [ -z "$end_line" ]; then
            content=$(cat "$input_file")
        else
            content=$(tail -n +$((end_line + 1)) "$input_file")
        fi

        # Convert markdown to HTML
        if [ "$MARKDOWN_PROCESSOR" = "pandoc" ]; then
            if ! html_content=$(echo "$content" | pandoc -f markdown -t html); then
                echo -e "${RED}Error: Markdown conversion failed for $input_file${NC}"
                return 1
            fi
        elif [ "$MARKDOWN_PROCESSOR" = "commonmark" ]; then
            if ! html_content=$(echo "$content" | cmark); then
                echo -e "${RED}Error: Markdown conversion failed for $input_file${NC}"
                return 1
            fi
        elif [ "$MARKDOWN_PROCESSOR" = "markdown.pl" ]; then
            if ! html_content=$(echo "$content" | perl "$MARKDOWN_PL_PATH"); then
                echo -e "${RED}Error: Markdown conversion failed for $input_file${NC}"
                return 1
            fi
        fi
    fi

    # Calculate reading time
    local reading_time
    reading_time=$(calculate_reading_time "$content")

    # Use pre-loaded templates
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"

    # Replace placeholders in the header
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"$title"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}

    # Determine if this is a page (as opposed to a post)
    local is_page=false
    if [[ "$input_file" == *"$PAGES_DIR"* ]]; then
        is_page=true
    fi

    # Set appropriate og:type
    if [ "$is_page" = true ]; then
        header_content=${header_content//\{\{og_type\}\}/"website"}
    else
        header_content=${header_content//\{\{og_type\}\}/"article"}
    fi

    # Remove image placeholders
    header_content=${header_content//\{\{og_image\}\}/""}
    header_content=${header_content//\{\{twitter_image\}\}/""}

    # Replace placeholders in the footer
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

    # Set proper URL in og:url
    local page_url="${output_base_path#$OUTPUT_DIR/}"
    if [[ "$page_url" == */ ]]; then
        page_url="${page_url%/}"
    fi
    header_content=${header_content//\{\{page_url\}\}/"$page_url"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}

    # Generate appropriate schema JSON-LD
    local schema_json_ld=""
    local tmp_schema=$(mktemp)

    if [ "$is_page" = true ]; then
        # WebPage schema for regular pages
        cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "WebPage",
  "name": "$title",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL/$page_url/",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
    else
        # Article schema for posts
        cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "$title",
  "description": "$SITE_DESCRIPTION",
  "datePublished": "$date",
  "author": {
    "@type": "Person",
    "name": "$AUTHOR_NAME"
  },
  "publisher": {
    "@type": "Organization",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  },
  "mainEntityOfPage": {
    "@type": "WebPage",
    "@id": "$SITE_URL/$page_url/"
  }
}
</script>
EOF
    fi

    # Read the schema from the temporary file
    schema_json_ld=$(cat "$tmp_schema")
    
    # Remove the temporary file
    rm "$tmp_schema"
    
    # Add schema markup to header
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

    # Create the complete HTML
    mkdir -p "$output_base_path"

    if [ "$is_page" = true ]; then
        # For pages: no date or reading time
        cat > "$output_base_path/index.html" << EOF
$header_content
<div class="page-header">
    <h1 class="page-title">$title</h1>
</div>
EOF
    else
        # For posts: include date and reading time
        cat > "$output_base_path/index.html" << EOF
$header_content
<div class="page-header">
    <h1 class="page-title">$title</h1>
    <div class="page-meta">${MSG_PUBLISHED_ON:-"Published on"} $(format_date "$date") • $(printf "${MSG_READING_TIME_TEMPLATE:-%d min read}" "$reading_time")</div>
</div>
EOF
    fi

    # Add featured image if specified
    if [ -n "$image" ]; then
        cat >> "$output_base_path/index.html" << EOF
<div class="featured-image">
    <img src="$image" alt="${title}" />
    ${image_caption:+<div class="image-caption">$image_caption</div>}
</div>
EOF
    fi

    cat >> "$output_base_path/index.html" << EOF
<div class="page-content">
$html_content
</div>
EOF

    # Add tags if present
    if [ -n "$tags_html" ]; then
        cat >> "$output_base_path/index.html" << EOF
$tags_html
EOF
    fi

    # Add footer
    cat >> "$output_base_path/index.html" << EOF
$footer_content
EOF

    echo -e "Processed page: ${GREEN}$(basename "$input_file")${NC}"
}

# Generate pages index
generate_pages_index() {
    echo -e "${YELLOW}Generating pages index...${NC}"
    
    # Skip if there are no secondary pages
    if [ ${#SECONDARY_PAGES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No secondary pages found, skipping pages index${NC}"
        return 0
    fi
    
    local pages_index="$OUTPUT_DIR/pages.html"
    
    # Prepare templates
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"
    
    # Replace placeholders in the header
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"All Pages"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    
    # Set og:type to website
    header_content=${header_content//\{\{og_type\}\}/"website"}
    
    # Set proper URL in og:url
    header_content=${header_content//\{\{page_url\}\}/"pages.html"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    
    # Generate CollectionPage schema
    local schema_json_ld=""
    local tmp_schema=$(mktemp)
    
    # Create CollectionPage schema
    cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "All Pages",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL/pages.html",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
    
    # Read the schema from the temporary file
    schema_json_ld=$(cat "$tmp_schema")
    
    # Remove the temporary file
    rm "$tmp_schema"
    
    # Add schema markup to header
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}
    
    # Remove image placeholders
    header_content=${header_content//\{\{og_image\}\}/""}
    header_content=${header_content//\{\{twitter_image\}\}/""}
    
    # Replace placeholders in the footer
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}
    
    # Create the pages index
    cat > "$pages_index" << EOF
$header_content
<h1>All Pages</h1>
<div class="posts-list">
EOF
    
    # Add all secondary pages to the index
    for page in "${SECONDARY_PAGES[@]}"; do
        IFS='|' read -r title url _ <<< "$page" # Ignore date for menu
        cat >> "$pages_index" << EOF
    <article>
        <h3><a href="$url">$title</a></h3>
    </article>
EOF
    done
    
    # Close the pages index
    cat >> "$pages_index" << EOF
</div>
$footer_content
EOF
    
    echo -e "${GREEN}Pages index generated!${NC}"
}

# Optimized file index building with parallel processing and smarter caching
optimized_build_file_index() {
    echo -e "${YELLOW}Building file index...${NC}"
    
    local file_index="$CACHE_DIR/file_index.txt"
    local file_index_tmp="$CACHE_DIR/file_index.tmp.$$"
    local index_marker="$CACHE_DIR/index_marker"
    local frontmatter_changes_marker="$CACHE_DIR/frontmatter_changes_marker"
    
    # Check if rebuild is needed by comparing the newest file in src directory with our marker
    if [ "$FORCE_REBUILD" = false ] && [ -f "$file_index" ] && [ -f "$index_marker" ]; then
        local newest_file
        if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
            # BSD systems
            newest_file=$(find "$SRC_DIR" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/\.*" -print0 | xargs -0 stat -f "%m" 2>/dev/null | sort -nr | head -1)
        else
            # Linux and other Unix-like systems
            newest_file=$(find "$SRC_DIR" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/\.*" -print0 | xargs -0 stat -c "%Y" 2>/dev/null | sort -nr | head -1)
        fi
        
        local marker_time=$(get_file_mtime "$index_marker")
        
        if [ -z "$newest_file" ] || [ "$newest_file" -le "$marker_time" ]; then
            echo -e "${GREEN}File index is up to date, skipping...${NC}"
            return 0
        fi
    fi
    
    # Get lock
    lock_file "$file_index"
    
    # Find all markdown files in the source directory
    # Get files in a more compatible way
    local all_files_tmp="$CACHE_DIR/all_files.tmp.$$"
    find "$SRC_DIR" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/\.*" | sort > "$all_files_tmp"
    
    # Show all found files
    echo "Found $(wc -l < "$all_files_tmp") files in source directory:"
    cat "$all_files_tmp"
    
    # Create temp directory for parallel processing
    local temp_dir="$CACHE_DIR/temp_index_$$"
    mkdir -p "$temp_dir"
    
    # Create metadata cache directory if it doesn't exist
    mkdir -p "$CACHE_DIR/meta"
    
    # Get number of available CPU cores for parallel processing
    local cores=1
    if command -v nproc > /dev/null 2>&1; then
        # Linux
        cores=$(nproc)
    elif command -v sysctl > /dev/null 2>&1; then
        # macOS, BSD
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    fi
    
    # Split files into batches for parallel processing
    local total_files=$(wc -l < "$all_files_tmp")
    local batch_size=$((total_files / cores + 1))
    
    # Make sure batch_size is at least 1
    if [ "$batch_size" -lt 1 ]; then
        batch_size=1
    fi
    
    echo -e "${YELLOW}Processing $total_files files using $cores cores...${NC}"
    
    # Export required functions and variables for parallel processing
    export DATE_FORMAT CACHE_DIR SRC_DIR
    export -f extract_metadata get_file_mtime format_date format_date_from_timestamp generate_slug generate_excerpt
    
    # Split files into batches
    split -l "$batch_size" "$all_files_tmp" "$temp_dir/batch_"
    
    # Process each batch in parallel
    for batch_file in "$temp_dir"/batch_*; do
        {
            local output_batch="$batch_file.out"
            > "$output_batch"  # Initialize empty file
            
            while read -r file; do
                # Skip hidden files
                if [[ $(basename "$file") == .* ]]; then
                    continue
                fi
                
                # Get filename without extension
                local filename=$(basename "$file" | sed 's/\.[^.]*$//')
                
                # Extract metadata from file
                local metadata
                metadata=$(extract_metadata "$file") || continue
                
                # Split metadata
                local title date tags slug image image_caption description
                IFS='|' read -r title date tags slug image image_caption description <<< "$metadata"
                
                # Add to batch file
                echo "$file|$filename|$title|$date|$tags|$slug|$image|$image_caption|$description" >> "$output_batch"
            done < "$batch_file"
        } &
        
        # Limit number of parallel processes to avoid system overload
        if [ $(jobs -p | wc -l) -ge $((cores * 2)) ]; then
            wait
        fi
    done
    
    # Wait for all background processes to finish
    wait
    
    # Merge batch files and ensure uniqueness
    > "$file_index_tmp"  # Initialize empty file
    for output_batch in "$temp_dir"/batch_*.out; do
        if [ -f "$output_batch" ]; then
            cat "$output_batch" >> "$file_index_tmp"
        fi
    done
    
    # Ensure each file only appears once by filtering by the first field (file path)
    # Create a temporary file for the filtered content
    local file_index_filtered="$CACHE_DIR/file_index.filtered.$$"
    awk -F'|' '!seen[$1]++' "$file_index_tmp" > "$file_index_filtered"
    
    # Check if file_index has changed
    local frontmatter_changed=false
    if [ -f "$file_index" ]; then
        # Compare old and new file index to detect changes
        if ! diff -q "$file_index" "$file_index_filtered" > /dev/null 2>&1; then
            frontmatter_changed=true
        fi
    else
        # If there was no previous file_index, consider it a change
        frontmatter_changed=true
    fi
    
    # Replace the temporary index with the filtered one
    mv "$file_index_filtered" "$file_index"
    
    # Update frontmatter changes marker if needed
    if [ "$frontmatter_changed" = true ]; then
        touch "$frontmatter_changes_marker"
        echo -e "${YELLOW}Frontmatter changes detected, updating marker${NC}"
    fi
    
    # Check if all files were processed
    echo "Processed $(wc -l < "$file_index") out of $total_files files"
    
    # Create marker file with current timestamp
    touch "$index_marker"
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    rm -f "$all_files_tmp"
    
    # Release lock
    unlock_file "$file_index"
    
    echo -e "${GREEN}File index built with $(wc -l < "$file_index") files!${NC}"
}

# Post-process all generated HTML files to fix URLs
post_process_urls() {
    echo -e "${YELLOW}Post-processing URLs with SITE_URL...${NC}"
    
    # Skip if SITE_URL is just http://localhost (default)
    if [ "$SITE_URL" = "http://localhost" ]; then
        echo -e "${YELLOW}SITE_URL is default, skipping URL post-processing${NC}"
        return 0
    fi
    
    # Find all HTML files in the output directory
    local html_files
    html_files=$(find "$OUTPUT_DIR" -type f -name "*.html")
    
    # Process each file
    for file in $html_files; do
        # Create a temporary file
        local temp_file=$(mktemp)
        
        # Replace href="/... with href="${SITE_URL}/...
        sed "s|href=\"/|href=\"${SITE_URL}/|g" "$file" > "$temp_file"
        
        # Replace src="/... with src="${SITE_URL}/...
        local temp_file2=$(mktemp)
        sed "s|src=\"/|src=\"${SITE_URL}/|g" "$temp_file" > "$temp_file2"
        
        # Move the temp file back to the original
        mv "$temp_file2" "$file"
        rm -f "$temp_file"
    done
    
    # Process XML files (RSS, sitemaps)
    local xml_files
    xml_files=$(find "$OUTPUT_DIR" -type f -name "*.xml")
    
    # Process each file
    for file in $xml_files; do
        # Create a temporary file
        local temp_file=$(mktemp)
        
        # Replace URLs in XML files
        sed "s|<loc>/|<loc>${SITE_URL}/|g" "$file" > "$temp_file"
        
        # Move the temp file back to the original
        mv "$temp_file" "$file"
    done
    
    # Process CSS files for any url() references
    local css_files
    css_files=$(find "$OUTPUT_DIR" -type f -name "*.css")
    
    # Process each file
    for file in $css_files; do
        # Create temporary files for each step
        local temp_file=$(mktemp)
        local temp_file2=$(mktemp)
        local temp_file3=$(mktemp)
        
        # Replace url('/... with url('${SITE_URL}/...
        sed "s|url('/|url('${SITE_URL}/|g" "$file" > "$temp_file"
        
        # Replace url("/... with url("${SITE_URL}/...
        sed "s|url(\"/|url(\"${SITE_URL}/|g" "$temp_file" > "$temp_file2"
        
        # Replace url(/... with url(${SITE_URL}/...
        sed "s|url(/|url(${SITE_URL}/|g" "$temp_file2" > "$temp_file3"
        
        # Move the final temp file back to the original
        mv "$temp_file3" "$file"
        
        # Clean up temp files
        rm -f "$temp_file" "$temp_file2"
    done
    
    echo -e "${GREEN}URL post-processing complete!${NC}"
}

# Main function to build the site
build_site() {
    echo -e "${YELLOW}Building site...${NC}"

    # Record start time
    local start_time=$(date +%s)

    # Load templates once
    preload_templates

    # Build file index
    optimized_build_file_index

    # Process all files
    process_all_markdown_files
    process_all_pages

    # Build tags index and generate tag pages
    build_tags_index
    generate_tag_pages

    # Build archive index and generate archive pages if enabled
    if [ "$ENABLE_ARCHIVES" = true ]; then
        build_archive_index
        generate_archive_pages
    fi

    # Generate pages index if there are secondary pages
    generate_pages_index

    # Generate index pages, sitemap and RSS feed
    generate_index
    generate_sitemap
    generate_rss
    
    # Post-process all URLs to ensure they're absolute
    post_process_urls

    # Record end time and print build duration
    local end_time=$(date +%s)
    local build_time=$((end_time - start_time))
    echo -e "${GREEN}Site built successfully in $build_time seconds!${NC}"
}

# Main function
main() {
    echo "BSSG - Bash Static Site Generator"
    echo "======================================================"

    # Load default configuration if file exists
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${GREEN}Configuration loaded from $CONFIG_FILE${NC}"
    else
        echo -e "${YELLOW}Configuration file $CONFIG_FILE not found, using defaults.${NC}"
    fi

    # Check for local config file before parsing arguments
    if [ -f "${CONFIG_FILE}.local" ]; then
        source "${CONFIG_FILE}.local"
        echo -e "${GREEN}Local configuration loaded from ${CONFIG_FILE}.local${NC}"
    fi

    # ---- Start Locale Loading ----
    # Function to print error messages in red
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

    # Parse command line arguments
    parse_args "$@"

    # Check dependencies
    check_dependencies

    # Clean output directory if option is enabled
    clean_output_directory

    # Check directories
    check_directories
    
    # Create cache directory structure if it doesn't exist
    mkdir -p "$CACHE_DIR"
    mkdir -p "$CACHE_DIR/meta"
    mkdir -p "$CACHE_DIR/content"
    
    # Store the current theme for theme change detection
    if [ ! -f "$CACHE_DIR/theme.txt" ]; then
        echo "$THEME" > "$CACHE_DIR/theme.txt"
    fi
    
    # Generate config hash if it doesn't exist
    if [ ! -f "$CONFIG_HASH_FILE" ]; then
        create_config_hash
    fi
    
    # Check if only the theme has changed
    if only_theme_changed; then
        # If only the theme changed, don't force rebuild of content
        # But we need to copy the theme files
        echo -e "${YELLOW}Only theme changed, using existing content cache${NC}"
    elif config_has_changed && [ "$FORCE_REBUILD" = false ]; then
        # If other configs changed (not just theme), force a rebuild
        # but only if force rebuild isn't already set
        echo -e "${YELLOW}Configuration changed, forcing rebuild...${NC}"
        FORCE_REBUILD=true
    fi

    # Create CSS
    source scripts/css.sh && create_css "$OUTPUT_DIR" "$THEME"

    # Copy static files
    copy_static_files

    # Build the site
    build_site

    # Fix permissions in output directory
    fix_output_permissions

    echo -e "\n${GREEN}Site generation complete!${NC}"
    echo -e "Generated site available in: ${YELLOW}$OUTPUT_DIR${NC}"
}

# Function to fix permissions in the output directory
fix_output_permissions() {
    echo "Setting proper permissions for output directory content..."
    
    # Make all files readable by all users
    find "$OUTPUT_DIR" -type f -exec chmod a+r {} \;
    
    # Make all directories readable and executable by all users
    find "$OUTPUT_DIR" -type d -exec chmod a+rx {} \;
    
    echo -e "${GREEN}Permissions set successfully!${NC}"
}

# Set markdown processor path only if using markdown.pl
if [ "$MARKDOWN_PROCESSOR" = "markdown.pl" ]; then
    if [ -f "./markdown.pl" ]; then
        MARKDOWN_PL_PATH="./markdown.pl"
    elif [ -f "./Markdown.pl" ]; then
        MARKDOWN_PL_PATH="./Markdown.pl"
    elif [ -f "$(dirname "$0")/../markdown.pl" ]; then
        MARKDOWN_PL_PATH="$(dirname "$0")/../markdown.pl"
    elif [ -f "$(dirname "$0")/../Markdown.pl" ]; then
        MARKDOWN_PL_PATH="$(dirname "$0")/../Markdown.pl"
    else
        echo -e "${RED}Error: Could not find markdown.pl or Markdown.pl${NC}"
        exit 1
    fi

    # Ensure the markdown processor is executable
    chmod +x "$MARKDOWN_PL_PATH"
fi

# Run the main function
main "$@"
