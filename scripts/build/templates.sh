#!/usr/bin/env bash
#
# BSSG - Template Handling
# Functions for loading and pre-processing templates.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from templates.sh"; exit 1; }
# shellcheck source=content.sh disable=SC1091
source "$(dirname "$0")/content.sh" || { echo >&2 "Error: Failed to source content.sh from templates.sh"; exit 1; }

# --- Global Template Variables and Cache --- START ---
HEADER_TEMPLATE=""
FOOTER_TEMPLATE=""
POST_TEMPLATE=""
PAGE_TEMPLATE=""
INDEX_TEMPLATE=""
TAG_TEMPLATE=""
ARCHIVE_TEMPLATE=""

declare -A TEMPLATE_CACHE

# Global array for secondary pages
declare -a SECONDARY_PAGES=()
# Global array for primary pages (used for sitemap)
declare -a primary_pages=()

# Cache directory for templates (might be needed by load_template)
TEMPLATE_CACHE_DIR="${CACHE_DIR:-.bssg_cache}/templates"

# --- Global Template Variables and Cache --- END ---

# --- Template Functions --- START ---

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

# Function to pre-load all templates and process menus/placeholders
preload_templates() {
    # Create template cache directory if it doesn't exist
    if [ "${BSSG_RAM_MODE:-false}" != true ]; then
        mkdir -p "$TEMPLATE_CACHE_DIR"
    fi

    local template_dir
    local templates_to_load=("header.html" "footer.html" "post.html" "page.html" "index.html" "tag.html" "archive.html")

    # --- Use TEMPLATES_DIR directly --- 
    # Always load structural HTML templates from the directory specified by TEMPLATES_DIR.
    # Themes are only responsible for style.css (handled in assets.sh).
    template_dir="${TEMPLATES_DIR:-templates}"
    
    # Check if the base template directory exists
    if [ ! -d "$template_dir" ]; then
        echo -e "${RED}Error: Base template directory '$template_dir' (defined by TEMPLATES_DIR) not found! Cannot load templates.${NC}" >&2
         HEADER_TEMPLATE="" FOOTER_TEMPLATE="" POST_TEMPLATE="" PAGE_TEMPLATE="" INDEX_TEMPLATE="" TAG_TEMPLATE="" ARCHIVE_TEMPLATE="" # Clear templates
         return 1 # Indicate error
    fi
    
    echo -e "${GREEN}Loading structural templates from $template_dir (defined by TEMPLATES_DIR)${NC}"

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
        # Optional: Add warning if a standard template is missing?
        # else
        #    echo -e "${YELLOW}Warning: Template file $template_dir/$tmpl not found.${NC}"
        fi
    done

    # Generate dynamic menu items from pages
    # IMPORTANT: Requires PAGES_DIR, SITE_URL, PAGE_URL_FORMAT, MSG_* vars to be exported/available
    # Assumes parse_metadata function is available (sourced via utils.sh or content.sh)
    local menu_items="<a href=\"${SITE_URL}/\">${MSG_HOME:-"Home"}</a>"
    local footer_items="<a href=\"${SITE_URL}/\">${MSG_HOME:-"Home"}</a> &middot;"

    # Arrays to store primary and secondary pages
    # Ensure we reset the global arrays before populating
    primary_pages=() # Operate on the global array
    SECONDARY_PAGES=()  # Reset global array

    # Scan pages directory for markdown and HTML files
    if [ -d "${PAGES_DIR:-pages}" ]; then
        local page_files=()
        if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_list_page_files > /dev/null; then
            mapfile -t page_files < <(ram_mode_list_page_files)
        else
            page_files=($(find "${PAGES_DIR:-pages}" -type f \( -name "*.md" -o -name "*.html" \) | sort))
        fi

        for file in "${page_files[@]}"; do
            # Skip if file is hidden
            if [[ $(basename "$file") == .* ]]; then
                continue
            fi

            # Extract title, slug, date, and secondary flag
            local title slug date secondary
            if [[ "$file" == *.html ]]; then
                # Crude HTML parsing - assumes specific meta tags exist
                local html_source=""
                if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$file"; then
                    html_source=$(ram_mode_get_content "$file")
                    title=$(printf '%s\n' "$html_source" | grep -m 1 '<title>' 2>/dev/null | sed 's/<[^>]*>//g')
                    slug=$(printf '%s\n' "$html_source" | grep -m 1 'meta name="slug"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
                    date=$(printf '%s\n' "$html_source" | grep -m 1 'meta name="date"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
                    secondary=$(printf '%s\n' "$html_source" | grep -m 1 'meta name="secondary"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
                else
                    title=$(grep -m 1 '<title>' "$file" 2>/dev/null | sed 's/<[^>]*>//g')
                    slug=$(grep -m 1 'meta name="slug"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
                    date=$(grep -m 1 'meta name="date"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/') # Extract date from meta
                    secondary=$(grep -m 1 'meta name="secondary"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
                fi
            else
                # Assumes parse_metadata is available
                title=$(parse_metadata "$file" "title")
                slug=$(parse_metadata "$file" "slug")
                date=$(parse_metadata "$file" "date") # Extract date from frontmatter
                secondary=$(parse_metadata "$file" "secondary")
            fi

            # If no slug is specified, generate from filename
            if [ -z "$slug" ]; then
                # Assumes generate_slug is available
                slug=$(generate_slug "$(basename "$file" | sed 's/\.[^.]*$//')")
            fi
            # Default title if empty
            if [ -z "$title" ]; then title="$(basename "$file" | sed 's/\.[^.]*$//')"; fi

            # Create URL based on PAGE_URL_FORMAT, remove double slashes
            local url
            url=$(echo "/${PAGE_URL_FORMAT//slug/$slug}/" | sed 's|//|/|g')

            # Store page info based on secondary flag (include date and source file)
            if [ "$secondary" = "true" ]; then
                SECONDARY_PAGES+=("$title|${SITE_URL}$url|$date|$file") # Added source file path
            else
                primary_pages+=("$title|${SITE_URL}$url|$date|$file") # Added source file path
            fi
        done
    fi

    # Add primary pages to menu
    for page in "${primary_pages[@]}"; do
        IFS='|' read -r title url _ _ <<< "$page" # Ignore date and source file for menu

        # Extract path part from the URL (relative to SITE_URL)
        local path_part="${url#$SITE_URL}" # Remove SITE_URL prefix
        path_part="${path_part#/}"       # Remove leading slash if exists
        path_part="${path_part%/}"      # Remove trailing slash if exists
        
        # Extract the final component (slug) using basename
        local current_slug=$(basename "$path_part")
        
        # Skip adding the 'index' page to the menu
        if [[ "$current_slug" == "index" ]]; then
            continue
        fi

        menu_items+=" <a href=\"$url\">$title</a>"
        footer_items+=" <a href=\"$url\">$title</a> &middot;"
    done

    # Add Pages menu item if there are secondary pages
    if [ ${#SECONDARY_PAGES[@]} -gt 0 ]; then
        menu_items+=" <a href=\"${SITE_URL}/pages.html\">${MSG_PAGES:-"Pages"}</a>"
        footer_items+=" <a href=\"${SITE_URL}/pages.html\">${MSG_PAGES:-"Pages"}</a> &middot;"
    fi

    # Add standard menu items
    local tags_flag_file="${CACHE_DIR:-.bssg_cache}/has_tags.flag"
    local has_tags=false
    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        [ -n "$(ram_mode_get_dataset "has_tags")" ] && has_tags=true
    elif [ -f "$tags_flag_file" ]; then
        has_tags=true
    fi
    # Add tags link only if tags are present.
    if [ "$has_tags" = true ]; then
        menu_items+=" <a href=\"${SITE_URL}/tags/\">${MSG_TAGS:-"Tags"}</a>"
    fi

    # Add Authors link if enabled and multiple authors exist
    local authors_flag_file="${CACHE_DIR:-.bssg_cache}/has_authors.flag"
    if [ "${ENABLE_AUTHOR_PAGES:-true}" = true ]; then
        # Check if we have multiple authors (more than the threshold)
        local authors_index_file="${CACHE_DIR:-.bssg_cache}/authors_index.txt"
        local unique_author_count=0
        if [ "${BSSG_RAM_MODE:-false}" = true ]; then
            local authors_index_data
            authors_index_data=$(ram_mode_get_dataset "authors_index")
            if [ -n "$authors_index_data" ]; then
                unique_author_count=$(printf '%s\n' "$authors_index_data" | awk -F'|' 'NF { print $1 }' | sort -u | wc -l | tr -d ' ')
            fi
        elif [ -f "$authors_index_file" ] && [ -f "$authors_flag_file" ]; then
            unique_author_count=$(awk -F'|' '{print $1}' "$authors_index_file" | sort -u | wc -l)
        fi
        if [ "$unique_author_count" -gt 0 ]; then
            local threshold="${SHOW_AUTHORS_MENU_THRESHOLD:-2}"
            if [ "$unique_author_count" -ge "$threshold" ]; then
                menu_items+=" <a href=\"${SITE_URL}/authors/\">${MSG_AUTHORS:-"Authors"}</a>"
            fi
        fi
    fi

    # Only add Archives link if enabled
    if [ "${ENABLE_ARCHIVES:-true}" = true ]; then
      menu_items+=" <a href=\"${SITE_URL}/archives/\">${MSG_ARCHIVES:-"Archives"}</a>"
      footer_items+=" <a href=\"${SITE_URL}/archives/\">${MSG_ARCHIVES:-"Archives"}</a> &middot;"
    fi
    menu_items+=" <a href=\"${SITE_URL}/${RSS_FILENAME:-rss.xml}\">${MSG_RSS:-"RSS"}</a>"

    # Add tags link to footer only if the flag file exists
    if [ "$has_tags" = true ]; then
        footer_items+=" <a href=\"${SITE_URL}/tags/\">${MSG_TAGS:-"Tags"}</a> &middot;"
    fi

    # Add Authors link to footer if enabled and multiple authors exist
    if [ "${ENABLE_AUTHOR_PAGES:-true}" = true ]; then
        local unique_author_count_footer=0
        if [ "${BSSG_RAM_MODE:-false}" = true ]; then
            local authors_index_data_footer
            authors_index_data_footer=$(ram_mode_get_dataset "authors_index")
            if [ -n "$authors_index_data_footer" ]; then
                unique_author_count_footer=$(printf '%s\n' "$authors_index_data_footer" | awk -F'|' 'NF { print $1 }' | sort -u | wc -l | tr -d ' ')
            fi
        elif [ -f "$authors_index_file" ] && [ -f "$authors_flag_file" ]; then
            unique_author_count_footer=$(awk -F'|' '{print $1}' "$authors_index_file" | sort -u | wc -l)
        fi
        if [ "$unique_author_count_footer" -gt 0 ]; then
            local threshold_footer="${SHOW_AUTHORS_MENU_THRESHOLD:-2}"
            if [ "$unique_author_count_footer" -ge "$threshold_footer" ]; then
                footer_items+=" <a href=\"${SITE_URL}/authors/\">${MSG_AUTHORS:-"Authors"}</a> &middot;"
            fi
        fi
    fi

    footer_items+=" <a href=\"${SITE_URL}/${RSS_FILENAME:-rss.xml}\">${MSG_SUBSCRIBE_RSS:-"Subscribe via RSS"}</a>"

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

    # --- Add RSS Filename Placeholder --- START ---
    HEADER_TEMPLATE=$(echo "$HEADER_TEMPLATE" | sed "s|{{[[:space:]]*rss_filename[[:space:]]*}}|${RSS_FILENAME:-rss.xml}|g")
    # --- Add RSS Filename Placeholder --- END ---

    # --- Handle Custom CSS --- START ---
    local custom_css_tag=""
    if [ -n "$CUSTOM_CSS" ]; then
        # Ensure CUSTOM_CSS starts with / if not empty
        local custom_css_path="$CUSTOM_CSS"
        if [[ "$custom_css_path" != /* ]]; then
            custom_css_path="/$custom_css_path"
        fi
        # Construct the link tag
        custom_css_tag="<link rel=\"stylesheet\" href=\"{{site_url}}${custom_css_path}\">"
        # Replace {{site_url}} within the tag itself
        custom_css_tag=$(echo "$custom_css_tag" | sed "s|{{site_url}}|${SITE_URL}|g")
        print_info "Adding custom CSS link: $CUSTOM_CSS"
    else
        print_info "No CUSTOM_CSS specified, skipping link."
    fi
    # Replace the placeholder in the header template
    HEADER_TEMPLATE=$(echo "$HEADER_TEMPLATE" | sed "s|{{[[:space:]]*custom_css_link[[:space:]]*}}|${custom_css_tag}|")
    # --- Handle Custom CSS --- END ---

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        ram_mode_set_dataset "primary_pages" "$(printf '%s\n' "${primary_pages[@]}")"
        ram_mode_set_dataset "secondary_pages" "$(printf '%s\n' "${SECONDARY_PAGES[@]}")"
    else
        # Write primary and secondary page lists to cache files only if changed
        local primary_pages_cache="$CACHE_DIR/primary_pages.tmp"
        local secondary_pages_cache="$CACHE_DIR/secondary_pages.tmp"
        local secondary_pages_list_file="$CACHE_DIR/secondary_pages.list" # <-- Define list file path
        
        # Prepare content in temporary files
        local primary_tmp=$(mktemp)
        local secondary_tmp=$(mktemp)
        local secondary_list_tmp=$(mktemp) # <-- Temp file for the list
        
        # Write current content to temporary files
        # Use printf for safer writing
        for page in "${primary_pages[@]}"; do
            printf "%s\n" "$page" >> "$primary_tmp"
        done
        for page in "${SECONDARY_PAGES[@]}"; do
            # Write to the temp file for comparison
            printf "%s\n" "$page" >> "$secondary_tmp"
            # Also write to the list temp file, one per line
            printf "%s\n" "$page" >> "$secondary_list_tmp"
        done

        # Function to compare and update cache file
        update_cache_if_changed() {
            local temp_file="$1"
            local cache_file="$2"
            local file_desc="$3"

            if [ ! -f "$cache_file" ] || ! cmp -s "$temp_file" "$cache_file"; then
                mv "$temp_file" "$cache_file"
                # echo "DEBUG: Updated $file_desc cache file." # Optional debug
            else
                rm "$temp_file"
                # echo "DEBUG: $file_desc cache file unchanged." # Optional debug
            fi
        }

        # Compare and update cache files
        update_cache_if_changed "$primary_tmp" "$primary_pages_cache"
        update_cache_if_changed "$secondary_tmp" "$secondary_pages_cache"
        update_cache_if_changed "$secondary_list_tmp" "$secondary_pages_list_file" # <-- Update the list file

        # Clean up temporary files
        rm -f "$primary_tmp" "$secondary_tmp" "$secondary_list_tmp" # <-- Cleanup list temp file
    fi

    echo -e "${GREEN}Templates pre-processed (menus, locale placeholders).${NC}"
}

# --- Template Functions --- END ---

# --- Exports --- START ---
# Export loaded templates and page lists for use by other scripts/parallel processes
export HEADER_TEMPLATE
export FOOTER_TEMPLATE
# Export others ONLY if directly needed by parallel processes elsewhere
# export POST_TEMPLATE PAGE_TEMPLATE INDEX_TEMPLATE TAG_TEMPLATE ARCHIVE_TEMPLATE

# Export arrays (convert to string for export) - REMOVED, using cache files instead
# export SECONDARY_PAGES="$(declare -p SECONDARY_PAGES | sed 's/declare -a SECONDARY_PAGES=//')"
# export primary_pages="$(declare -p primary_pages | sed 's/declare -a primary_pages=//')"
# If array export is problematic, preload_templates could write page lists to cache files instead
# --- Exports --- END --- 

# Export functions - Do not export the SECONDARY_PAGES array itself anymore
export -f preload_templates 
# export SECONDARY_PAGES # <-- Remove this export 
