#!/usr/bin/env bash
#
# BSSG - Build Orchestrator
# Main script to coordinate the static site build process.
#

set -e # Exit immediately if a command exits with a non-zero status.

echo "BSSG Build Process - Starting..."
BUILD_START_TIME=$(date +%s)

# Determine the base directory of the scripts/build folder
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Determine the project root (one level up from the SCRIPT_DIR's parent)
PROJECT_ROOT="$( dirname "$( dirname "$SCRIPT_DIR" )" )"
export BSSG_PROJECT_ROOT="$PROJECT_ROOT"
# Check if PROJECT_ROOT is already the current directory to avoid unnecessary cd
if [ "$PWD" != "$PROJECT_ROOT" ]; then
  echo "Changing directory to project root: $PROJECT_ROOT"
  cd "$PROJECT_ROOT" # Ensure we run from the project root
else
  echo "Already in project root: $PROJECT_ROOT"
fi

# --- Load Config First ---
# Configuration and arguments are now expected to be handled by the calling script (bssg.sh)
# and passed via exported environment variables. We assume variables like SRC_DIR,
# OUTPUT_DIR, THEME, FORCE_REBUILD, etc., are already set in the environment.

# --- Parse CLI Arguments ---
# Argument parsing is now handled by bssg.sh. Specific build options might still
# be passed, but core config like --config is handled before this script runs.
# We may need to parse specific build flags later if needed.

# Placeholder for any potential build-specific argument parsing if necessary in the future

# --- Handle Random Theme (after CLI parsing) --- START ---
# Random theme logic might need adjustment if THEME is purely from env var
# Check if THEME is set to 'random' from the environment
if [[ "${THEME:-default}" == "random" ]]; then
    echo -e "${YELLOW}Theme set to random, selecting a random theme...${NC}"
    # Find available themes (directories in THEMES_DIR)
    available_themes=()
    if [ -d "${THEMES_DIR:-themes}" ]; then
        for d in "${THEMES_DIR:-themes}"/*; do
            if [ -d "$d" ]; then
                theme_name=$(basename "$d")
                # Exclude "random" itself if it exists as a directory
                if [[ "$theme_name" != "random" ]]; then
                    available_themes+=("$theme_name")
                fi
            fi
        done
    fi
    
    num_themes=${#available_themes[@]}
    if [ "$num_themes" -gt 0 ]; then
        # Select a random theme index
        random_index=$(( RANDOM % num_themes ))
        THEME="${available_themes[$random_index]}"
        echo -e "${GREEN}Randomly selected theme: $THEME${NC}"
    else
        echo -e "${RED}Error: No themes found in '$THEMES_DIR' to select randomly. Defaulting to 'default'.${NC}"
        THEME="default"
    fi
fi
# --- Handle Random Theme --- END ---

# Re-export variables potentially overridden by parse_args.
# This is no longer strictly necessary as the calling script exports them,
# but keep it for now in case some build-specific args modify env vars locally.
# echo "Re-exporting variables potentially set by CLI..."
# export SRC_DIR OUTPUT_DIR TEMPLATES_DIR THEMES_DIR STATIC_DIR THEME
# export SITE_TITLE SITE_DESCRIPTION SITE_URL AUTHOR_NAME AUTHOR_EMAIL
# export POSTS_PER_PAGE CLEAN_OUTPUT FORCE_REBUILD CONFIG_FILE
# export PAGES_DIR DRAFTS_DIR
# Add any other variable that parse_args can change

# Source Utilities (needs sourced colors) AFTER config/cli
# Source Utilities - MUST BE SOURCED FIRST to get print_info etc.
# Needs to happen before any potential print statements.
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh" || { echo -e "\033[0;31mError: Failed to source utils.sh\033[0m"; exit 1; }

# Build mode validation and setup
BUILD_MODE="${BUILD_MODE:-normal}"
case "$BUILD_MODE" in
    normal|ram) ;;
    *)
        echo -e "${RED}Error: Invalid BUILD_MODE '$BUILD_MODE'. Use 'normal' or 'ram'.${NC}" >&2
        exit 1
        ;;
esac
export BUILD_MODE
export BSSG_RAM_MODE=false

# Print the theme being used for this build (final value after potential random selection)
echo -e "${GREEN}Using theme: ${THEME}${NC}"

echo "Loaded utilities."

# --- RAM Mode Stage Timing --- START ---
BSSG_RAM_TIMING_ENABLED=false
if [ "$BUILD_MODE" = "ram" ]; then
    BSSG_RAM_TIMING_ENABLED=true
fi
declare -ga BSSG_RAM_TIMING_STAGE_KEYS=()
declare -ga BSSG_RAM_TIMING_STAGE_LABELS=()
declare -ga BSSG_RAM_TIMING_STAGE_MS=()
BSSG_RAM_TIMING_STAGE_ACTIVE=false
BSSG_RAM_TIMING_CURRENT_STAGE_KEY=""
BSSG_RAM_TIMING_CURRENT_STAGE_LABEL=""
BSSG_RAM_TIMING_CURRENT_STAGE_START_MS=0

_bssg_ram_timing_now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local epoch_norm sec frac ms_part
        # Some locales expose EPOCHREALTIME with ',' instead of '.' as decimal separator.
        epoch_norm="${EPOCHREALTIME/,/.}"
        if [[ "$epoch_norm" =~ ^([0-9]+)([.][0-9]+)?$ ]]; then
            sec="${BASH_REMATCH[1]}"
            frac="${BASH_REMATCH[2]#.}"
            frac="${frac}000"
            ms_part="${frac:0:3}"
            printf '%s\n' $(( 10#$sec * 1000 + 10#$ms_part ))
            return
        fi
    fi

    if command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf("%.0f\n", time()*1000)'
    else
        printf '%s\n' $(( $(date +%s) * 1000 ))
    fi
}

_bssg_ram_timing_format_ms() {
    local ms="$1"
    printf '%d.%03ds' $((ms / 1000)) $((ms % 1000))
}

bssg_ram_timing_start() {
    if [ "$BSSG_RAM_TIMING_ENABLED" != true ]; then
        return
    fi

    if [ "$BSSG_RAM_TIMING_STAGE_ACTIVE" = true ]; then
        bssg_ram_timing_end
    fi

    BSSG_RAM_TIMING_CURRENT_STAGE_KEY="$1"
    BSSG_RAM_TIMING_CURRENT_STAGE_LABEL="$2"
    BSSG_RAM_TIMING_CURRENT_STAGE_START_MS="$(_bssg_ram_timing_now_ms)"
    BSSG_RAM_TIMING_STAGE_ACTIVE=true
}

bssg_ram_timing_end() {
    if [ "$BSSG_RAM_TIMING_ENABLED" != true ] || [ "$BSSG_RAM_TIMING_STAGE_ACTIVE" != true ]; then
        return
    fi

    local end_ms elapsed_ms
    end_ms="$(_bssg_ram_timing_now_ms)"
    elapsed_ms=$((end_ms - BSSG_RAM_TIMING_CURRENT_STAGE_START_MS))
    if [ "$elapsed_ms" -lt 0 ]; then
        elapsed_ms=0
    fi

    BSSG_RAM_TIMING_STAGE_KEYS+=("$BSSG_RAM_TIMING_CURRENT_STAGE_KEY")
    BSSG_RAM_TIMING_STAGE_LABELS+=("$BSSG_RAM_TIMING_CURRENT_STAGE_LABEL")
    BSSG_RAM_TIMING_STAGE_MS+=("$elapsed_ms")

    BSSG_RAM_TIMING_STAGE_ACTIVE=false
    BSSG_RAM_TIMING_CURRENT_STAGE_KEY=""
    BSSG_RAM_TIMING_CURRENT_STAGE_LABEL=""
    BSSG_RAM_TIMING_CURRENT_STAGE_START_MS=0
}

bssg_ram_timing_print_summary() {
    if [ "$BSSG_RAM_TIMING_ENABLED" != true ]; then
        return
    fi

    # Close any open stage (defensive; build flow should end stages explicitly).
    if [ "$BSSG_RAM_TIMING_STAGE_ACTIVE" = true ]; then
        bssg_ram_timing_end
    fi

    local count="${#BSSG_RAM_TIMING_STAGE_MS[@]}"
    if [ "$count" -eq 0 ]; then
        return
    fi

    local total_ms=0
    local max_ms=0
    local max_label=""
    local i
    for ((i = 0; i < count; i++)); do
        local stage_ms="${BSSG_RAM_TIMING_STAGE_MS[$i]}"
        total_ms=$((total_ms + stage_ms))
        if [ "$stage_ms" -gt "$max_ms" ]; then
            max_ms="$stage_ms"
            max_label="${BSSG_RAM_TIMING_STAGE_LABELS[$i]}"
        fi
    done

    echo "------------------------------------------------------"
    echo -e "${GREEN}RAM mode timing summary:${NC}"
    printf "  %-26s %12s %10s\n" "Stage" "Duration" "Share"
    for ((i = 0; i < count; i++)); do
        local stage_label="${BSSG_RAM_TIMING_STAGE_LABELS[$i]}"
        local stage_ms="${BSSG_RAM_TIMING_STAGE_MS[$i]}"
        local pct_tenths=0
        if [ "$total_ms" -gt 0 ]; then
            pct_tenths=$(( (stage_ms * 1000 + total_ms / 2) / total_ms ))
        fi
        local formatted_ms
        formatted_ms="$(_bssg_ram_timing_format_ms "$stage_ms")"
        printf "  %-26s %12s %6d.%d%%\n" "$stage_label" "$formatted_ms" $((pct_tenths / 10)) $((pct_tenths % 10))
    done
    echo -e "  ${GREEN}Total (timed stages):$(_bssg_ram_timing_format_ms "$total_ms")${NC}"
    if [ -n "$max_label" ]; then
        echo -e "  ${YELLOW}Slowest stage:${NC} ${max_label} ($(_bssg_ram_timing_format_ms "$max_ms"))"
    fi
}
# --- RAM Mode Stage Timing --- END ---

# Check Dependencies
# shellcheck source=deps.sh
bssg_ram_timing_start "dependencies" "Dependencies"
source "${SCRIPT_DIR}/deps.sh" || { echo -e "${RED}Error: Failed to source deps.sh${NC}"; exit 1; }
check_dependencies # Call the function to perform checks and export HAS_PARALLEL
bssg_ram_timing_end

if [ "$BUILD_MODE" = "ram" ]; then
    export BSSG_RAM_MODE=true
    export FORCE_REBUILD=true

    # shellcheck source=ram_mode.sh
    source "${SCRIPT_DIR}/ram_mode.sh" || { echo -e "${RED}Error: Failed to source ram_mode.sh${NC}"; exit 1; }
    print_info "RAM mode enabled: source/template files and build indexes are held in memory."
    print_info "RAM mode parallel worker cap: ${RAM_MODE_MAX_JOBS:-6} (set RAM_MODE_MAX_JOBS to tune)."
fi

echo "Checked dependencies. Parallel available: ${HAS_PARALLEL:-false}"

# Source Cache Manager (defines cache functions)
# shellcheck source=cache.sh
bssg_ram_timing_start "cache_setup" "Cache Setup/Clean"
source "${SCRIPT_DIR}/cache.sh" || { echo -e "${RED}Error: Failed to source cache.sh${NC}"; exit 1; }
echo "Loaded cache manager."

# Check if config changed BEFORE updating the hash file, store status for later use
BSSG_CONFIG_CHANGED_STATUS=1 # Default to 1 (not changed)
if [ "${BSSG_RAM_MODE:-false}" = true ]; then
    # RAM mode is intentionally ephemeral, always rebuild from preloaded inputs.
    BSSG_CONFIG_CHANGED_STATUS=0
elif config_has_changed; then
    BSSG_CONFIG_CHANGED_STATUS=0 # Set to 0 (changed)
fi
export BSSG_CONFIG_CHANGED_STATUS

# --- Initial Cache Setup & Cleaning --- START
# IMPORTANT: CACHE_DIR must be defined (usually in config) and available

# --- Add check for CLEAN_OUTPUT influencing FORCE_REBUILD --- START ---
if [ "${CLEAN_OUTPUT:-false}" = true ]; then
    if [ "${FORCE_REBUILD:-false}" != true ]; then
        echo -e "${YELLOW}Clean output requested (--clean-output), forcing rebuild (--force-rebuild)...${NC}"
        FORCE_REBUILD=true
        export FORCE_REBUILD # Ensure the variable is exported if changed here
    fi
fi
# --- Add check for CLEAN_OUTPUT influencing FORCE_REBUILD --- END ---

# Handle --force-rebuild first
if [ "${BSSG_RAM_MODE:-false}" != true ] && [ "${FORCE_REBUILD:-false}" = true ]; then
    echo -e "${YELLOW}Force rebuild enabled, deleting entire cache directory (${CACHE_DIR:-.bssg_cache})...${NC}"
    rm -rf "${CACHE_DIR:-.bssg_cache}"
    echo -e "${GREEN}Cache deleted!${NC}"
fi

if [ "${BSSG_RAM_MODE:-false}" != true ]; then
    echo "Ensuring cache directory structure exists... (${CACHE_DIR:-.bssg_cache})"
    mkdir -p "${CACHE_DIR:-.bssg_cache}/meta" "${CACHE_DIR:-.bssg_cache}/content"

    # Create initial config hash *after* ensuring cache dir exists
    create_config_hash
else
    echo "RAM mode: skipping cache directory creation and config hash persistence."
fi
# --- Initial Cache Setup & Cleaning --- END

# Handle --clean-output flag (using logic moved from original main/clean_output_directory)
if [ "${CLEAN_OUTPUT:-false}" = true ]; then
    echo -e "${YELLOW}Cleaning output directory (${OUTPUT_DIR:-output})...${NC}"
    if [ -d "${OUTPUT_DIR:-output}" ]; then
        # Make sure OUTPUT_DIR is not empty or / before removing
        if [ -n "${OUTPUT_DIR:-output}" ] && [ "${OUTPUT_DIR:-output}" != "/" ]; then
             rm -rf "${OUTPUT_DIR:?}"/* # Safe rm -rf requires var to be non-empty
             echo -e "${GREEN}Output directory cleaned!${NC}"
        else
             echo -e "${RED}Error: Cannot clean - OUTPUT_DIR is empty or set to root directory!${NC}"
             # Optionally exit here if this is considered a fatal error
             # exit 1
        fi
    else
        echo -e "${YELLOW}Output directory (${OUTPUT_DIR:-output}) does not exist, no need to clean.${NC}"
    fi
fi
bssg_ram_timing_end

# Source Content Processor (defines functions like extract_metadata, convert_markdown_to_html)
# Moved up before indexing as indexing uses some content functions (e.g., generate_slug)
# shellcheck source=content.sh
bssg_ram_timing_start "index_build" "Index/Data Build"
source "${SCRIPT_DIR}/content.sh" || { echo -e "${RED}Error: Failed to source content.sh${NC}"; exit 1; }
echo "Loaded content processing functions."

# Source Indexing Script (defines index building functions)
# Moved up before preload_templates
# shellcheck source=indexing.sh
source "${SCRIPT_DIR}/indexing.sh" || { echo -e "${RED}Error: Failed to source indexing.sh${NC}"; exit 1; }
echo "Loaded indexing functions."

if [ "${BSSG_RAM_MODE:-false}" = true ]; then
    ram_mode_preload_inputs || { echo -e "${RED}Error: RAM preload failed.${NC}"; exit 1; }
fi

# --- Build Intermediate Indexes ---
# Moved up before preload_templates
# --- Start Change: Snapshot previous file index ---
file_index_file="${CACHE_DIR:-.bssg_cache}/file_index.txt"
file_index_prev_file="${CACHE_DIR:-.bssg_cache}/file_index_prev.txt"
if [ "${BSSG_RAM_MODE:-false}" != true ]; then
    if [ -f "$file_index_file" ]; then
        echo "Snapshotting previous file index to $file_index_prev_file" >&2 # Debug
        cp "$file_index_file" "$file_index_prev_file"
    else
        # Ensure previous file doesn't exist if current doesn't
        rm -f "$file_index_prev_file"
    fi
fi
# --- End Change ---
optimized_build_file_index || { echo -e "${RED}Error: Failed to build file index.${NC}"; exit 1; }

# --- Start Change: Snapshot previous tags index ---
tags_index_file="${CACHE_DIR:-.bssg_cache}/tags_index.txt"
tags_index_prev_file="${CACHE_DIR:-.bssg_cache}/tags_index_prev.txt"
if [ "${BSSG_RAM_MODE:-false}" != true ]; then
    if [ -f "$tags_index_file" ]; then
        echo "Snapshotting previous tags index to $tags_index_prev_file" >&2 # Debug
        cp "$tags_index_file" "$tags_index_prev_file"
    else
        # Ensure previous file doesn't exist if current doesn't
        rm -f "$tags_index_prev_file"
    fi
fi
# --- End Change ---

build_tags_index || { echo -e "${RED}Error: Failed to build tags index.${NC}"; exit 1; }

# --- Start Debug: Show tags_index.txt content ---
# echo "DEBUG: Content of $tags_index_file after build:" >&2
# cat "$tags_index_file" >&2
# echo "--- End $tags_index_file DEBUG ---" >&2
# --- End Debug ---

# --- Start Change: Snapshot previous authors index ---
authors_index_file="${CACHE_DIR:-.bssg_cache}/authors_index.txt"
authors_index_prev_file="${CACHE_DIR:-.bssg_cache}/authors_index_prev.txt"
if [ "${BSSG_RAM_MODE:-false}" != true ]; then
    if [ -f "$authors_index_file" ]; then
        echo "Snapshotting previous authors index to $authors_index_prev_file" >&2 # Debug
        cp "$authors_index_file" "$authors_index_prev_file"
    else
        # Ensure previous file doesn't exist if current doesn't
        rm -f "$authors_index_prev_file"
    fi
fi
# --- End Change ---

build_authors_index || { echo -e "${RED}Error: Failed to build authors index.${NC}"; exit 1; }

# --- Start Change: Identify affected authors ---
identify_affected_authors || { echo -e "${RED}Error: Failed to identify affected authors.${NC}"; exit 1; }
# --- End Change ---

if [ "${ENABLE_ARCHIVES:-false}" = true ]; then
    # --- Start Change: Snapshot previous archive index ---
    archive_index_file="${CACHE_DIR:-.bssg_cache}/archive_index.txt"
    archive_index_prev_file="${CACHE_DIR:-.bssg_cache}/archive_index_prev.txt"
    if [ "${BSSG_RAM_MODE:-false}" != true ]; then
        if [ -f "$archive_index_file" ]; then
            echo "Snapshotting previous archive index to $archive_index_prev_file" >&2 # Debug
            cp "$archive_index_file" "$archive_index_prev_file"
        else
            # Ensure previous file doesn't exist if current doesn't
            rm -f "$archive_index_prev_file"
        fi
    fi
    # --- End Change ---
    build_archive_index || { echo -e "${RED}Error: Failed to build archive index.${NC}"; exit 1; }
    # --- Start Change: Identify affected archive months ---
    identify_affected_archive_months || { echo -e "${RED}Error: Failed to identify affected archive months.${NC}"; exit 1; }
    # --- End Change ---
fi
echo "Built intermediate cache indexes."
bssg_ram_timing_end

# Load Templates (and generate dynamic menus, exports vars like HEADER_TEMPLATE)
# Moved down after indexing
# shellcheck source=templates.sh
bssg_ram_timing_start "templates" "Template Prep"
source "${SCRIPT_DIR}/templates.sh" || { echo -e "${RED}Error: Failed to source templates.sh${NC}"; exit 1; }
preload_templates # Call the function
echo "Loaded and processed templates."

# --- Pre-calculate Max Template/Locale Time --- START ---
# Moved down, should happen after templates are loaded
echo "Pre-calculating latest template/locale modification time..."
# IMPORTANT: Requires TEMPLATES_DIR, THEMES_DIR, THEME, LOCALE_DIR, SITE_LANG, get_file_mtime to be available
latest_template_locale_time=0

# Determine active template directory
active_template_dir="${TEMPLATES_DIR:-templates}"
if [ -d "$active_template_dir/${THEME:-default}" ]; then
    active_template_dir="$active_template_dir/${THEME:-default}"
fi
header_template_file="$active_template_dir/header.html"
footer_template_file="$active_template_dir/footer.html"

# Determine active locale file
active_locale_file=""
if [ -f "${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh" ]; then
    active_locale_file="${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh"
elif [ -f "${LOCALE_DIR:-locales}/en.sh" ]; then # Fallback to en.sh
    active_locale_file="${LOCALE_DIR:-locales}/en.sh"
fi

# Get timestamps (returns 0 if file doesn't exist)
header_time=$(get_file_mtime "$header_template_file")
footer_time=$(get_file_mtime "$footer_template_file")
locale_time=$(get_file_mtime "$active_locale_file")

# Find the maximum time
latest_template_locale_time=$header_time
if (( footer_time > latest_template_locale_time )); then
    latest_template_locale_time=$footer_time
fi
if (( locale_time > latest_template_locale_time )); then
    latest_template_locale_time=$locale_time
fi

export BSSG_MAX_TEMPLATE_LOCALE_TIME=$latest_template_locale_time
echo "Latest template/locale time: $BSSG_MAX_TEMPLATE_LOCALE_TIME (Header: $header_time, Footer: $footer_time, Locale: $locale_time)"
# --- Pre-calculate Max Template/Locale Time --- END ---
bssg_ram_timing_end

# --- Prepare for Parallel Processing ---
if [ "${HAS_PARALLEL:-false}" = true ]; then
    echo "Exporting functions and variables for parallel processing..."
    # Export general utility/content/cache functions needed by multiple generation steps
    # Specific generation functions (e.g., process_single_file) are exported within their respective scripts before parallel call
    export -f file_needs_rebuild common_rebuild_check get_file_mtime lock_file unlock_file # from cache.sh
    export -f format_date format_date_from_timestamp generate_slug calculate_reading_time fix_url # from utils.sh
    export -f extract_metadata parse_metadata generate_excerpt convert_markdown_to_html # from content.sh

    # Essential variables (already exported by loaders, but ensures availability)
    export CACHE_DIR FORCE_REBUILD POSTS_DIR PAGES_DIR OUTPUT_DIR SITE_URL SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME
    export HEADER_TEMPLATE FOOTER_TEMPLATE POST_URL_FORMAT PAGE_URL_FORMAT BASE_URL PRETTY_URLS
    export CACHE_READING_TIME READING_TIME_WPM MARKDOWN_PROCESSOR MARKDOWN_PL_PATH DATE_FORMAT TIMEZONE SHOW_TIMEZONE
    # Export the pre-calculated time for parallel jobs
    export BSSG_MAX_TEMPLATE_LOCALE_TIME

    echo "Core parallel exports complete."
fi

# --- Related Posts Cache Invalidation --- START ---
# This will be handled during post processing for better timing
RELATED_POSTS_INVALIDATED_LIST=""
if [ "${ENABLE_RELATED_POSTS:-true}" = true ]; then
    # Export the variable for use by generate_posts.sh
    export RELATED_POSTS_INVALIDATED_LIST
fi
# --- Related Posts Cache Invalidation --- END ---

# --- Generate Content HTML ---
# Source and run Post Generator
# shellcheck source=generate_posts.sh
bssg_ram_timing_start "posts" "Posts"
source "${SCRIPT_DIR}/generate_posts.sh" || { echo -e "${RED}Error: Failed to source generate_posts.sh${NC}"; exit 1; }
process_all_markdown_files || { echo -e "${RED}Error: Post processing failed.${NC}"; exit 1; }
echo "Generated post HTML files."
bssg_ram_timing_end

# --- Post Generation --- END ---

# --- Page Generation --- START --
# Source the page generation script
# shellcheck source=generate_pages.sh disable=SC1091
bssg_ram_timing_start "pages" "Static Pages"
source "$SCRIPT_DIR/generate_pages.sh" || { echo -e "${RED}Error: Failed to source generate_pages.sh${NC}"; exit 1; }
# Call the main page processing function
process_all_pages || { echo -e "${RED}Error: Page processing failed.${NC}"; exit 1; }
bssg_ram_timing_end
# --- Page Generation --- END ---

# --- Tag Page Generation --- START ---
# Source and run Tag Page Generator
# shellcheck source=generate_tags.sh disable=SC1091
bssg_ram_timing_start "tags" "Tags"
source "$SCRIPT_DIR/generate_tags.sh" || { echo -e "${RED}Error: Failed to source generate_tags.sh${NC}"; exit 1; }
# Call the main function from the sourced script
generate_tag_pages || { echo -e "${RED}Error: Tag page generation failed.${NC}"; exit 1; }
echo "Generated tag list pages."
bssg_ram_timing_end
# --- Tag Page Generation --- END ---

# --- Author Page Generation --- START ---
# Source and run Author Page Generator (if enabled)
if [ "${ENABLE_AUTHOR_PAGES:-true}" = true ]; then
    bssg_ram_timing_start "authors" "Authors"
    # shellcheck source=generate_authors.sh disable=SC1091
    source "$SCRIPT_DIR/generate_authors.sh" || { echo -e "${RED}Error: Failed to source generate_authors.sh${NC}"; exit 1; }
    
    # Call the main generation function 
    # It will internally use AFFECTED_AUTHORS and AUTHORS_INDEX_NEEDS_REBUILD
    generate_author_pages || { echo -e "${RED}Error: Author page generation failed.${NC}"; exit 1; }
    echo "Generated author pages."
    bssg_ram_timing_end
fi
# --- Author Page Generation --- END ---

# --- Archive Page Generation --- START ---
# Source and run Archive Page Generator (if enabled)
if [ "${ENABLE_ARCHIVES:-false}" = true ]; then
    bssg_ram_timing_start "archives" "Archives"
    # Source the script (loads functions)
    # shellcheck source=generate_archives.sh disable=SC1091
    source "$SCRIPT_DIR/generate_archives.sh" || { echo -e "${RED}Error: Failed to source generate_archives.sh${NC}"; exit 1; }
    
    # Call the main generation function 
    # It will internally use AFFECTED_ARCHIVE_MONTHS and ARCHIVE_INDEX_NEEDS_REBUILD
    generate_archive_pages || { echo -e "${RED}Error: Archive page generation failed.${NC}"; exit 1; }
    echo "Generated archive pages."
    bssg_ram_timing_end
fi
# --- Archive Page Generation --- END ---

# --- Main Index Page Generation --- START ---
# Source and run Main Index Page Generator
# shellcheck source=generate_index.sh disable=SC1091
bssg_ram_timing_start "main_index" "Main Index"
source "$SCRIPT_DIR/generate_index.sh" || { echo -e "${RED}Error: Failed to source generate_index.sh${NC}"; exit 1; }
# Call the main function from the sourced script
generate_index || { echo -e "${RED}Error: Index page generation failed.${NC}"; exit 1; }
echo "Generated main index/pagination pages."
bssg_ram_timing_end
# --- Main Index Page Generation --- END ---

# --- Feed Generation --- START ---
# Source and run Feed Generator
# shellcheck source=generate_feeds.sh disable=SC1091
bssg_ram_timing_start "feeds" "Sitemap/RSS"
source "$SCRIPT_DIR/generate_feeds.sh" || { echo -e "${RED}Error: Failed to source generate_feeds.sh${NC}"; exit 1; }
# Call the functions from the sourced script
echo "Timing sitemap generation..."
if [ "${BSSG_RAM_MODE:-false}" = true ]; then
    echo "Timing RSS feed generation..."
    feed_jobs=0
    feed_jobs=$(get_parallel_jobs)
    if [ "$feed_jobs" -gt 1 ]; then
        echo "RAM mode: generating sitemap and RSS in parallel..."

        sitemap_failed=false
        rss_failed=false

        generate_sitemap &
        sitemap_pid=$!

        generate_rss &
        rss_pid=$!

        if ! wait "$sitemap_pid"; then
            sitemap_failed=true
        fi
        if ! wait "$rss_pid"; then
            rss_failed=true
        fi

        if $sitemap_failed; then
            echo -e "${YELLOW}Sitemap generation failed, continuing build...${NC}"
        fi
        if $rss_failed; then
            echo -e "${YELLOW}RSS feed generation failed, continuing build...${NC}"
        fi
    else
        generate_sitemap || echo -e "${YELLOW}Sitemap generation failed, continuing build...${NC}" # Allow failure
        generate_rss || echo -e "${YELLOW}RSS feed generation failed, continuing build...${NC}" # Allow failure
    fi
else
    generate_sitemap || echo -e "${YELLOW}Sitemap generation failed, continuing build...${NC}" # Allow failure
    echo "Timing RSS feed generation..."
    generate_rss || echo -e "${YELLOW}RSS feed generation failed, continuing build...${NC}" # Allow failure
fi
echo "Generated RSS feed and sitemap."
bssg_ram_timing_end
# --- Feed Generation --- END ---

# --- Secondary Pages Index Generation --- START ---
# Source and run Secondary Pages Index Generator (if secondary pages exist)
# Check if the SECONDARY_PAGES array exported by templates.sh is non-empty
# Note: Checking exported arrays directly can be tricky.
# We attempt to reconstruct the array from the exported string.
# shellcheck disable=SC2154 # SECONDARY_PAGES is exported by templates.sh
if [ -n "$SECONDARY_PAGES" ] && [ "$SECONDARY_PAGES" != "()" ]; then
    bssg_ram_timing_start "secondary_index" "Secondary Index"
    # shellcheck source=generate_secondary_pages.sh disable=SC1091
    source "$SCRIPT_DIR/generate_secondary_pages.sh" || { echo -e "${RED}Error: Failed to source generate_secondary_pages.sh${NC}"; exit 1; }
    generate_pages_index || echo -e "${YELLOW}Secondary pages index generation failed, continuing build...${NC}" # Allow failure
    echo "Generated secondary pages index."
    bssg_ram_timing_end
else
    echo "No secondary pages defined, skipping secondary index generation."
fi
# --- Secondary Pages Index Generation --- END ---

# --- Asset Handling --- START ---
# Source the asset handling script
# shellcheck source=assets.sh disable=SC1091
bssg_ram_timing_start "assets" "Assets/CSS"
source "$SCRIPT_DIR/assets.sh" || { echo -e "${RED}Error: Failed to source assets.sh${NC}"; exit 1; }
# Copy static assets
echo "Timing static files copy..."
copy_static_files || { echo -e "${RED}Error: Failed to copy static assets.${NC}"; exit 1; }
# Process CSS files (includes theme asset copy)
echo "Timing CSS/Theme processing..."
create_css "$OUTPUT_DIR" "$THEME" || { echo -e "${RED}Error: Failed to process CSS.${NC}"; exit 1; } # Pass OUTPUT_DIR and THEME
echo "Handled static assets and CSS."
bssg_ram_timing_end
# --- Asset Handling --- END ---

# --- Post Processing --- START ---
# Source and run Post Processor
# shellcheck source=post_process.sh disable=SC1091
bssg_ram_timing_start "post_process" "Post Processing"
source "$SCRIPT_DIR/post_process.sh" || { echo -e "${RED}Error: Failed to source post_process.sh${NC}"; exit 1; }
echo "Timing URL post-processing..."
post_process_urls || echo -e "${YELLOW}URL post-processing failed, continuing...${NC}" # Allow failure
echo "Timing output permissions fix..."
fix_output_permissions || echo -e "${YELLOW}Fixing output permissions failed, continuing...${NC}" # Allow failure
echo "Completed post-processing."
bssg_ram_timing_end
# --- Post Processing --- END ---

# --- Final Cache Update --- START ---
if [ "${BSSG_RAM_MODE:-false}" != true ]; then
    create_config_hash
fi
# --- Final Cache Update --- END ---

# --- Final Cleanup --- START ---
if [ "${BSSG_RAM_MODE:-false}" != true ]; then
    echo "Cleaning up previous index files..."
    rm -f "${CACHE_DIR:-.bssg_cache}/file_index_prev.txt"
    rm -f "${CACHE_DIR:-.bssg_cache}/tags_index_prev.txt"
    rm -f "${CACHE_DIR:-.bssg_cache}/authors_index_prev.txt"
    rm -f "${CACHE_DIR:-.bssg_cache}/archive_index_prev.txt"

    # Remove the frontmatter changes marker if it exists
    rm -f "${CACHE_DIR:-.bssg_cache}/frontmatter_changes_marker"

    # Clean up related posts temporary files to prevent unnecessary cache invalidation on next build
    rm -f "${CACHE_DIR:-.bssg_cache}/modified_tags.list"
    rm -f "${CACHE_DIR:-.bssg_cache}/modified_authors.list"
    rm -f "${CACHE_DIR:-.bssg_cache}/related_posts_invalidated.list"
fi

# --- Final Cleanup --- END ---

# --- Pre-compress Assets --- START ---
_precompress_single_file() {
    local file="$1"
    local gzfile="$2"
    local compression_level="$3"
    local verbose_logs="$4"

    if [ "$verbose_logs" = "true" ]; then
        echo "Compressing: $file"
    fi
    gzip -c "-${compression_level}" -- "$file" > "$gzfile"
}

precompress_assets() {
    # Check if pre-compression is enabled in the config.
    if [ ! "${PRECOMPRESS_ASSETS:-false}" = "true" ]; then
        return
    fi

    echo "Starting pre-compression of assets..."
    local compression_level="${PRECOMPRESS_GZIP_LEVEL:-9}"
    if ! [[ "$compression_level" =~ ^[1-9]$ ]]; then
        compression_level=9
    fi
    local verbose_logs="${PRECOMPRESS_VERBOSE:-${RAM_MODE_VERBOSE:-false}}"

    # 1. Cleanup: Remove any .gz file that does not have a corresponding original file.
    # This handles cases where original files were deleted.
    # Using -print0 and read -d '' to safely handle filenames with spaces or special chars.
    find "${OUTPUT_DIR}" -type f -name "*.gz" -print0 | while IFS= read -r -d '' gzfile; do
        original_file="${gzfile%.gz}"
        if [ ! -f "$original_file" ]; then
            echo "Removing stale compressed file: $gzfile"
            rm -- "$gzfile"
        fi
    done

    # 2. Compression: Compress text files if they are new or have been updated.
    # We target .html, .css, .xml and .js files.
    local changed_files=()
    while IFS= read -r -d '' file; do
        local gzfile="${file}.gz"
        # Compress if the .gz file doesn't exist, or if the original file is newer.
        if [ ! -f "$gzfile" ] || [ "$file" -nt "$gzfile" ]; then
            changed_files+=("$file")
        fi
    done < <(find "${OUTPUT_DIR}" -type f \( -name "*.html" -o -name "*.css" -o -name "*.xml" -o -name "*.js" \) -print0)

    if [ "${#changed_files[@]}" -eq 0 ]; then
        echo "No changed assets to pre-compress."
        echo "Asset pre-compression finished."
        return
    fi

    local compress_jobs
    compress_jobs=$(get_parallel_jobs "${PRECOMPRESS_MAX_JOBS:-0}")
    if [ "$compress_jobs" -gt "${#changed_files[@]}" ]; then
        compress_jobs="${#changed_files[@]}"
    fi

    if [ "$compress_jobs" -gt 1 ]; then
        local file gzfile q_file q_gzfile q_level q_verbose
        q_level=$(printf '%q' "$compression_level")
        q_verbose=$(printf '%q' "$verbose_logs")
        run_parallel "$compress_jobs" < <(
            for file in "${changed_files[@]}"; do
                gzfile="${file}.gz"
                q_file=$(printf '%q' "$file")
                q_gzfile=$(printf '%q' "$gzfile")
                printf "_precompress_single_file %s %s %s %s\n" "$q_file" "$q_gzfile" "$q_level" "$q_verbose"
            done
        ) || { echo -e "${RED}Asset pre-compression failed.${NC}"; return 1; }
    else
        local file gzfile
        for file in "${changed_files[@]}"; do
            gzfile="${file}.gz"
            _precompress_single_file "$file" "$gzfile" "$compression_level" "$verbose_logs" || {
                echo -e "${RED}Asset pre-compression failed for ${file}.${NC}"
                return 1
            }
        done
    fi

    echo "Pre-compressed ${#changed_files[@]} assets using ${compress_jobs} worker(s) (gzip -${compression_level})."

    echo "Asset pre-compression finished."
}

# Execute the asset compression.
bssg_ram_timing_start "precompress" "Pre-compress"
precompress_assets
bssg_ram_timing_end
# --- Pre-compress Assets --- END ---

# --- Deployment --- START ---
bssg_ram_timing_start "deployment" "Deployment Decision/Run"
deploy_now="false"
if [[ "${CMD_DEPLOY_OVERRIDE:-unset}" == "true" ]]; then # Use default value for safety
    deploy_now="true"
    echo -e "${YELLOW}Deployment forced via command line (--deploy).${NC}"
elif [[ "${CMD_DEPLOY_OVERRIDE:-unset}" == "false" ]]; then
    deploy_now="false"
    echo -e "${YELLOW}Deployment skipped via command line (--no-deploy).${NC}"
elif [[ "${DEPLOY_AFTER_BUILD:-false}" == "true" ]]; then
    deploy_now="true"
    echo "Deployment enabled via configuration (DEPLOY_AFTER_BUILD=true)."
else
    echo "Deployment not configured or explicitly disabled."
fi

if [[ "$deploy_now" == "true" ]]; then
    if [[ -n "${DEPLOY_SCRIPT:-}" ]]; then
        # Ensure the deploy script path is treated correctly (absolute, relative to project root, or starting with ~)
        effective_deploy_script="$DEPLOY_SCRIPT"

        # Handle tilde expansion first
        if [[ "$effective_deploy_script" == "~/"* ]]; then
            # Replace leading "~/" with "$HOME/"
            effective_deploy_script="$HOME/${effective_deploy_script#\~/}"
        elif [[ "$effective_deploy_script" == "~" ]]; then
            # Handle the case where the path is just "~"
            effective_deploy_script="$HOME"
        fi

        # Now check if it's absolute or relative (after potential tilde expansion)
        if [[ ! "$effective_deploy_script" = /* ]]; then
            # If not absolute (doesn't start with /), assume relative to project root
            effective_deploy_script="${PROJECT_ROOT}/${effective_deploy_script}"
        fi

        # Check if the effective path exists and is a file
        if [[ -f "$effective_deploy_script" ]]; then
            if [[ -x "$effective_deploy_script" ]]; then
                echo -e "${GREEN}Executing deployment script: $effective_deploy_script...${NC}"
                DEPLOY_START_TIME=$(date +%s)
                # Execute the script from the project root context
                # Pass OUTPUT_DIR and SITE_URL as potentially useful arguments
                # Add error handling for the script execution itself
                if (cd "$PROJECT_ROOT" && "$effective_deploy_script" "$OUTPUT_DIR" "$SITE_URL"); then
                    DEPLOY_END_TIME=$(date +%s)
                    DEPLOY_DURATION=$((DEPLOY_END_TIME - DEPLOY_START_TIME))
                    echo -e "${GREEN}Deployment script finished successfully in ${DEPLOY_DURATION} seconds.${NC}"
                else
                    echo -e "${RED}Error: Deployment script '$effective_deploy_script' failed with exit code $?.${NC}"
                    # Decide if build should fail on deployment failure (e.g., exit 1)
                fi
            else
                echo -e "${RED}Error: Deployment script '$effective_deploy_script' is not executable.${NC}"
            fi
        else
            echo -e "${RED}Error: Deployment script '$effective_deploy_script' not found.${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: Deployment was requested, but DEPLOY_SCRIPT is not set in configuration.${NC}"
    fi
fi
bssg_ram_timing_end
# --- Deployment --- END ---

# --- End of execution ---

BUILD_END_TIME=$(date +%s)
BUILD_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))
bssg_ram_timing_print_summary
echo "------------------------------------------------------"
echo -e "${GREEN}Build process completed in ${BUILD_DURATION} seconds.${NC}"

exit 0 
