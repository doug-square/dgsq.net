#!/usr/bin/env bash
#
# BSSG - Cache Management Utilities
# Functions for handling build cache and rebuild checks.
#

# Define cache paths (should match exported config, but useful here too)
# CACHE_DIR=".bssg_cache" # Redundant: CACHE_DIR is now set and exported by config_loader.sh
CONFIG_HASH_FILE="${CACHE_DIR}/config_hash.md5" # Use variable directly
# Add other cache-related paths if directly used by functions below
# (Example: $CACHE_DIR/theme.txt, $CACHE_DIR/file_index.txt, etc. are used)

# --- Cache Functions --- START ---

# Create a hash of the current configuration
create_config_hash() {
    echo "Generating configuration hash..."

    # Dynamically build the config string from BSSG_CONFIG_VARS
    # IMPORTANT: Requires BSSG_CONFIG_VARS to be exported from config_loader.sh
    local config_string=""
    local var_name
    local config_vars_array
    # Read exported vars into an array
    read -r -a config_vars_array <<< "$BSSG_CONFIG_VARS"
    for var_name in "${config_vars_array[@]}"; do
        # Use printf -v to append safely, ensuring literal newlines
        printf -v config_string '%s%s=%s\n' "$config_string" "$var_name" "${!var_name}"
    done

    # Calculate MD5 hash of the config string
    local current_hash
    current_hash=$(echo -n "$config_string" | portable_md5sum | awk '{print $1}')

    # Check against stored hash before writing
    local stored_hash=""
    if [ -f "$CONFIG_HASH_FILE" ]; then
        stored_hash=$(cat "$CONFIG_HASH_FILE")
    fi

    # Only write if hash changed or file doesn't exist
    if [ "$current_hash" != "$stored_hash" ]; then
        echo "$current_hash" > "$CONFIG_HASH_FILE"
        echo -e "Configuration hash created/updated: ${GREEN}$current_hash${NC}"
    else
        echo -e "Configuration hash is up to date: ${GREEN}$current_hash${NC}"
    fi
}

# Check if configuration has changed since last build
config_has_changed() {
    # If no hash file exists, configuration has effectively changed
    if [ ! -f "$CONFIG_HASH_FILE" ]; then
        # echo "DEBUG_CACHE: No stored config hash found." >&2
        return 0  # True, config has changed
    fi

    # Dynamically build the config string from BSSG_CONFIG_VARS
    # IMPORTANT: Requires BSSG_CONFIG_VARS to be exported from config_loader.sh
    local config_string=""
    local var_name
    local config_vars_array
    # Read exported vars into an array
    read -r -a config_vars_array <<< "$BSSG_CONFIG_VARS"
    for var_name in "${config_vars_array[@]}"; do
        # Use printf -v to append safely, ensuring literal newlines
        printf -v config_string '%s%s=%s\n' "$config_string" "$var_name" "${!var_name}"
    done

    # Create current full hash using the portable wrapper
    local current_hash
    current_hash=$(echo -n "$config_string" | portable_md5sum | awk '{print $1}')

    # Read stored hash (which should also be a full hash)
    local stored_hash=$(cat "$CONFIG_HASH_FILE")

    # Compare hashes
    if [ "$current_hash" != "$stored_hash" ]; then
        # echo "DEBUG_CACHE: Config hash mismatch. Current='$current_hash' Stored='$stored_hash'" >&2
        # DO NOT overwrite the stored hash here. Only check.
        # echo "$current_hash" > "$CONFIG_HASH_FILE"
        return 0  # True, config has changed
    fi

    # echo "DEBUG_CACHE: Config hash matches." >&2 # Optional: Log match
    return 1  # False, config has not changed
}

# Check if only the theme has changed (not any other config settings)
# NOTE: This function might need adjustment if the dynamic hashing reveals
# other implicit theme-related changes that weren't previously tracked.
# For now, it assumes `config_has_changed` correctly reflects all non-theme changes.
only_theme_changed() {
    local theme_cache_file="${CACHE_DIR}/theme.txt"
    # If no hash file exists, more than just theme has changed
    if [ ! -f "$CONFIG_HASH_FILE" ] || [ ! -f "$theme_cache_file" ]; then
        return 1  # False, more than theme has changed
    fi

    # Read the stored theme
    local stored_theme
    stored_theme=$(cat "$theme_cache_file")

    # Compare current theme with stored theme
    if [ "$THEME" != "$stored_theme" ]; then
        echo -e "${YELLOW}Theme has changed from $stored_theme to $THEME${NC}"

        # Store the current theme for next time
        echo "$THEME" > "$theme_cache_file"

        # Check if any other config has changed
        if ! config_has_changed; then
            echo -e "${GREEN}Only theme has changed, will use cache where possible${NC}"
            return 0  # True, only theme has changed
        fi
    fi

    return 1  # False, more than theme has changed or theme hasn't changed
}

# Clean stale cache entries
clean_stale_cache() {
    # If FORCE_REBUILD is true, delete the entire cache directory and recreate it
    if [ "${FORCE_REBUILD:-false}" = true ]; then # Check exported FORCE_REBUILD
        echo -e "${YELLOW}Force rebuild enabled, deleting entire cache...${NC}"
        rm -rf "$CACHE_DIR"
        mkdir -p "$CACHE_DIR/meta"
        mkdir -p "$CACHE_DIR/content"
        echo -e "${GREEN}Cache deleted!${NC}"
        return
    fi

    echo -e "${YELLOW}Cleaning stale cache entries...${NC}"

    # Flag to track if any posts were removed
    local posts_removed=false

    # Get list of all source files from both src and pages directories
    # IMPORTANT: Requires SRC_DIR, PAGES_DIR to be exported/available
    local md_files=$(find "${SRC_DIR:-src}" "${PAGES_DIR:-pages}" -type f -name "*.md" 2>/dev/null | sort)

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
        rm -f "${CACHE_DIR}/tags_index.txt"
        rm -f "${CACHE_DIR}/archive_index.txt"
        rm -f "${CACHE_DIR}/index_marker"
        # Remove the tags flag file as well
        rm -f "${CACHE_DIR}/has_tags.flag"
        # IMPORTANT: Requires OUTPUT_DIR to be exported/available
        rm -f "${OUTPUT_DIR:-output}/sitemap.xml"
        rm -f "${OUTPUT_DIR:-output}/${RSS_FILENAME:-rss.xml}"
        rm -f "${OUTPUT_DIR:-output}/index.html"

        # Also remove tag and archive pages to force their regeneration
        find "${OUTPUT_DIR:-output}/tags" -name "*.html" -type f -delete 2>/dev/null || true
        find "${OUTPUT_DIR:-output}/archives" -name "*.html" -type f -delete 2>/dev/null || true
        
        # Clean related posts cache when posts are removed
        if [ -d "${CACHE_DIR}/related_posts" ]; then
            echo -e "${YELLOW}Cleaning related posts cache due to post removal...${NC}"
            rm -rf "${CACHE_DIR}/related_posts"
        fi
    fi

    echo -e "${GREEN}Cache cleaned!${NC}"
}

# Check if a rebuild is needed based on common conditions
common_rebuild_check() {
    local output_file_to_check="$1"
    # echo "DEBUG_CACHE: common_rebuild_check called for '$output_file_to_check'" >&2

    # Force rebuild if flag is set
    if [ "${FORCE_REBUILD:-false}" = true ]; then
        # echo "DEBUG_CACHE: Force rebuild flag set, returning 0" >&2
        return 0  # Rebuild needed
    fi

    # Check if configuration has changed using the pre-calculated status
    # IMPORTANT: Requires BSSG_CONFIG_CHANGED_STATUS to be exported from main.sh
    if [ "${BSSG_CONFIG_CHANGED_STATUS:-1}" -eq 0 ]; then # Default to 1 (not changed) if var unset
        # echo "DEBUG_CACHE: BSSG_CONFIG_CHANGED_STATUS=0, returning 0" >&2
        return 0  # Rebuild needed
    fi

    # Check if output file exists. If not, rebuild needed.
    # Moved this basic check here for clarity.
    if [ ! -f "$output_file_to_check" ]; then 
        # echo "DEBUG_CACHE: Output file '$output_file_to_check' missing, returning 0" >&2
        return 0 # Rebuild needed
    fi

    # Removed template/locale checks here. They are done in file_needs_rebuild now.

    # echo "DEBUG_CACHE: common_rebuild_check returning 1 (passed common checks)" >&2 
    return 1 # Common checks passed (config ok, not forced, output exists)
}

# Check if a rebuild is needed based on file timestamps and templates
file_needs_rebuild() {
    local input_file="$1"
    local output_file="$2"
    # echo "DEBUG_CACHE: file_needs_rebuild check for Input='$input_file' Output='$output_file'" >&2

    # Call the common rebuild check function (checks force, config, output existence)
    common_rebuild_check "$output_file"
    local common_result=$?
    # echo "DEBUG_CACHE: common_rebuild_check returned $common_result for '$output_file'" >&2

    # If common conditions already determined we need to rebuild
    if [ $common_result -eq 0 ]; then
        return 0  # Rebuild needed
    fi

    # At this point: Not forced, config OK, output file exists.
    # Now check against pre-calculated max template/locale time and input file time.

    # IMPORTANT: Assumes get_file_mtime is sourced from utils.sh
    # IMPORTANT: Requires BSSG_MAX_TEMPLATE_LOCALE_TIME to be exported from main.sh
    local output_time
    output_time=$(get_file_mtime "$output_file")

    # Check if templates/locale are newer than output
    # Default to 0 if variable is unset (should not happen if main.sh ran)
    if (( ${BSSG_MAX_TEMPLATE_LOCALE_TIME:-0} > output_time )); then
        # echo "DEBUG_CACHE: Templates/locale newer than output ($BSSG_MAX_TEMPLATE_LOCALE_TIME > $output_time), returning 0" >&2
        return 0 # Rebuild needed
    fi

    # Check if input file is newer than output file
    local input_time
    input_time=$(get_file_mtime "$input_file")
    if (( input_time > output_time )); then
        # echo "DEBUG_CACHE: Input newer than output ($input_time > $output_time), returning 0" >&2
        return 0  # Rebuild needed
    fi

    # echo "DEBUG_CACHE: file_needs_rebuild returning 1 (no rebuild) for '$output_file'" >&2
    return 1  # No rebuild needed
}

# Check if tags or indexes need rebuilding
indexes_need_rebuild() {
    # Check common rebuild conditions for the main index file
    # IMPORTANT: Requires OUTPUT_DIR to be exported/available
    local main_index="${OUTPUT_DIR:-output}/index.html"

    # Call the common rebuild check function
    common_rebuild_check "$main_index"
    local common_result=$?

    # If common conditions already determined we need to rebuild
    if [ $common_result -eq 0 ]; then
        return 0  # Rebuild needed
    fi

    # Check if any of the index files exist and are up to date
    local index_files=(
        "${OUTPUT_DIR:-output}/tags/index.html"
        "${OUTPUT_DIR:-output}/archives/index.html"
        "${OUTPUT_DIR:-output}/index.html"
        "${OUTPUT_DIR:-output}/rss.xml"
        "${OUTPUT_DIR:-output}/sitemap.xml"
    )

    # Get the latest template/locale time (using main index as baseline)
    # IMPORTANT: Assumes get_file_mtime is sourced/available
    local latest_base_time
    latest_base_time=$(get_file_mtime "$main_index")

    # Check if file_index.txt exists and is newer than the baseline
    local file_index="$CACHE_DIR/file_index.txt"
    if [ -f "$file_index" ]; then
        local file_index_time
        file_index_time=$(get_file_mtime "$file_index")
        if (( file_index_time > latest_base_time )); then
            latest_base_time=$file_index_time
            echo -e "${YELLOW}Source file list change detected, indexes need rebuild${NC}"
        fi
    fi

    # Check if frontmatter_changes_marker exists and is newer than baseline
    local frontmatter_changes_marker="$CACHE_DIR/frontmatter_changes_marker"
    if [ -f "$frontmatter_changes_marker" ]; then
        local marker_time
        marker_time=$(get_file_mtime "$frontmatter_changes_marker")
        if (( marker_time > latest_base_time )); then
            latest_base_time=$marker_time
            echo -e "${YELLOW}Frontmatter changes detected, indexes need rebuild${NC}"
        fi
    fi

    # Also check if metadata cache has changed (more robust than marker)
    local meta_cache_dir="$CACHE_DIR/meta"
    if [ -d "$meta_cache_dir" ]; then
        local newest_meta_time=0
        # Use find with -printf for efficiency if available
        if find --version >/dev/null 2>&1 && grep -q GNU <<< "$(find --version)"; then
             newest_meta_time=$(find "$meta_cache_dir" -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -n 1)
             newest_meta_time=${newest_meta_time:-0} # Handle empty dir
             # Convert float timestamp to integer
             newest_meta_time=${newest_meta_time%.*} # Truncate to integer
        else
             # Fallback for non-GNU find (less efficient)
             local meta_files
             meta_files=$(find "$meta_cache_dir" -type f 2>/dev/null)
             for meta_file in $meta_files; do
                 local meta_time
                 meta_time=$(get_file_mtime "$meta_file")
                 if (( meta_time > newest_meta_time )); then
                     newest_meta_time=$meta_time
                 fi
             done
        fi

        if (( newest_meta_time > latest_base_time )); then
            latest_base_time=$newest_meta_time
            echo -e "${YELLOW}Metadata cache change detected, indexes need rebuild${NC}"
        fi
    fi

    # Check if any index file is missing or older than the determined latest relevant time
    for index_file in "${index_files[@]}"; do
        # Skip check for archive index if archives disabled
        # IMPORTANT: Requires ENABLE_ARCHIVES to be exported/available
        if [[ "$index_file" == *"archives/index.html"* ]] && [ "${ENABLE_ARCHIVES:-true}" != true ]; then
            continue
        fi
        # IMPORTANT: Assumes get_file_mtime is sourced/available
        local index_file_time
        index_file_time=$(get_file_mtime "$index_file")
        if [ ! -f "$index_file" ] || (( index_file_time < latest_base_time )); then
            return 0  # Rebuild needed
        fi
    done

    return 1  # No rebuild needed
}

# --- Cache Functions --- END --- 