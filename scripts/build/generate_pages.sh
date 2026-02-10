#!/usr/bin/env bash
#
# BSSG - Static Page Generation
# Functions for converting markdown/HTML pages.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_pages.sh"; exit 1; }
# shellcheck source=content.sh disable=SC1091
source "$(dirname "$0")/content.sh" || { echo >&2 "Error: Failed to source content.sh from generate_pages.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_pages.sh"; exit 1; } # For file_needs_rebuild checks etc.

# --- Moved Function Definitions --- START ---

# Convert a page (Markdown or HTML) to final HTML output
convert_page() {
    local input_file="$1"
    local output_base_path="$2"
    local title="$3"
    local date="$4"
    local slug="$5"

    # IMPORTANT: Assumes CACHE_DIR, FORCE_REBUILD, PAGES_DIR, SITE_TITLE, SITE_DESCRIPTION, SITE_URL, AUTHOR_NAME are exported/available
    local output_html_file="$output_base_path/index.html"
    local ram_mode_active=false
    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$input_file"; then
        ram_mode_active=true
    fi

    # Check if the source file exists
    if ! $ram_mode_active && [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: Source page '$input_file' not found${NC}" >&2
        return 1
    fi

    # Skip if output file is newer than input file and no force rebuild
    # Uses file_needs_rebuild from cache.sh
    if ! file_needs_rebuild "$input_file" "$output_html_file"; then
        echo -e "Skipping unchanged page: ${YELLOW}$(basename "$input_file")${NC}"
        return 0
    fi

    echo -e "Processing page: ${GREEN}$(basename "$input_file")${NC}"

    local content="" # Content for reading time calculation (if markdown)
    local html_content="" # Final body HTML content

    if [[ "$input_file" == *.html ]]; then
        # For HTML files, extract content between <body> tags (simple approach)
        local html_source=""
        if $ram_mode_active; then
            html_source=$(ram_mode_get_content "$input_file")
        else
            html_source=$(cat "$input_file")
        fi
        html_content=$(printf '%s\n' "$html_source" | sed -n '/<body>/,/<\/body>/p' | sed '1d;$d')
        # We might not have raw content for reading time easily here
         content=$(echo "$html_content" | sed 's/<[^>]*>//g') # Basic text extraction for reading time
    else
        # For markdown files, extract content after frontmatter
        local source_stream=""
        if $ram_mode_active; then
            source_stream=$(ram_mode_get_content "$input_file")
        else
            source_stream=$(cat "$input_file")
        fi
        content=$(printf '%s\n' "$source_stream" | awk '
            BEGIN { in_fm = 0; found_fm = 0; }
            /^---$/ {
                if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
                if (in_fm) { in_fm = 0; next; }
            }
            { if (!in_fm) print; }
        ')

        # --- MODIFIED PART --- START ---
        # Convert markdown content to HTML using the function from content.sh
        html_content=$(convert_markdown_to_html "$content")
        if [ $? -ne 0 ]; then
            echo -e "${RED}Markdown conversion failed for page '$input_file', skipping html generation.${NC}" >&2
            return 1 # Propagate the error
        fi
        # --- MODIFIED PART --- END ---
    fi

    # Calculate reading time (best effort for HTML input)
    local reading_time
    reading_time=$(calculate_reading_time "$content")

    # Use pre-loaded templates
    # IMPORTANT: Assumes HEADER_TEMPLATE, FOOTER_TEMPLATE are exported/available
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"

    # Verify templates are not empty
    if [ -z "$header_content" ] || [ -z "$footer_content" ]; then
        echo -e "${RED}Error: Templates are empty in convert_page. Was templates.sh sourced correctly?${NC}" >&2
        return 1
    fi

    # Replace placeholders in the header
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"$title"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"} # Use site description for pages
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_type\}\}/"website"} # Pages are usually 'website' type
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    # Construct page URL based on format, ensuring trailing slash
    local formatted_page_path="${PAGE_URL_FORMAT//slug/$slug}"
    local page_rel_url="/$(echo "$formatted_page_path" | sed 's|^/||; s|/*$|/|')"
    header_content=${header_content//\{\{page_url\}\}/"$page_rel_url"}

    # Remove schema if it exists, or set default schema for WebPage
    local page_full_url="${SITE_URL}${page_rel_url}" # Construct full URL
    local schema_json_ld=$(printf '<script type="application/ld+json">\n{\n  "@context": "https://schema.org",\n  "@type": "WebPage",\n  "name": "%s",\n  "url": "%s",\n  "isPartOf": {\n    "@type": "WebSite",\n    "name": "%s",\n    "url": "%s"\n  }\n}\n</script>' \
        "$(echo "$title" | sed 's/"/\\"/g')" \
        "$page_full_url" \
        "$SITE_TITLE" \
        "$SITE_URL")
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

    # Handle image placeholders (remove for pages as they don't have featured images)
    header_content=${header_content//\{\{og_image\}\}/}
    header_content=${header_content//\{\{twitter_image\}\}/}

    # Assemble the final HTML
    local final_html="${header_content}"
    
    # Add page title and content (no post-meta for pages usually)
    final_html+=$(printf '<article class="page">\n  <h1>%s</h1>\n  <div class="page-content">\n%s\n  </div>\n</article>\n' "$title" "$html_content")

    # Replace placeholders in footer content before appending
    local current_year=$(date +'%Y')
    footer_content=${footer_content//\{\{current_year\}\}/$current_year}
    footer_content=${footer_content//\{\{author_name\}\}/${AUTHOR_NAME:-Anonymous}}

    # Append footer
    final_html+="${footer_content}"

    # Create output directory if it doesn't exist
    mkdir -p "$output_base_path"

    # Write the final HTML to the output file
    printf '%s' "$final_html" > "$output_html_file"
}

# Define a function for processing a single page file
process_single_page_file() {
    local file="$1"

    # Extract metadata (title, date, slug)
    # IMPORTANT: Assumes parse_metadata is available (content.sh)
    local title slug date
    if [[ "$file" == *.html ]]; then
        title=$(grep -m 1 '<title>' "$file" 2>/dev/null | sed 's/<[^>]*>//g')
        slug=$(grep -m 1 'meta name="slug"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        date=$(grep -m 1 'meta name="date"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
    else
        title=$(parse_metadata "$file" "title")
        slug=$(parse_metadata "$file" "slug")
        date=$(parse_metadata "$file" "date") # Date might be optional for pages
    fi

    # Fallback/Defaults
    if [ -z "$title" ]; then title=$(basename "$file" | sed 's/\.[^.]*$//'); fi
    if [ -z "$slug" ]; then slug=$(generate_slug "$title"); fi # Use generate_slug (utils.sh)

    # Create output path based on PAGE_URL_FORMAT
    # IMPORTANT: Assumes PAGE_URL_FORMAT, OUTPUT_DIR are exported/available
    local formatted_path="${PAGE_URL_FORMAT//slug/$slug}"
    # Ensure the path represents the directory for index.html
    local output_path="${OUTPUT_DIR:-output}/$(echo "$formatted_path" | sed 's|^/||; s|/*$||')"

    # Call the modified convert_page function (defined above in this script)
    convert_page "$file" "$output_path" "$title" "$date" "$slug"
}

# --- Moved Function Definitions --- END ---

# --- Page Generation Functions --- START ---

# Process all pages found in the PAGES_DIR
process_all_pages() {
    echo -e "${YELLOW}Processing static pages...${NC}"

    # IMPORTANT: Assumes PAGES_DIR is exported/available
    if [ ! -d "${PAGES_DIR:-pages}" ]; then
        echo -e "${YELLOW}Pages directory ('${PAGES_DIR:-pages}') not found, skipping page processing.${NC}"
        return 0
    fi

    # Use mapfile -t to read sorted files into array (newline-separated, trailing newline stripped)
    local page_files=()
    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_list_page_files > /dev/null; then
        mapfile -t page_files < <(ram_mode_list_page_files)
    else
        mapfile -t page_files < <(find "${PAGES_DIR:-pages}" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" | sort)
    fi

    local num_pages=${#page_files[@]}
    if [ "$num_pages" -eq 0 ]; then
        echo -e "${YELLOW}No pages found in '${PAGES_DIR:-pages}'. Skipping page generation.${NC}"
        return 0
    fi
    echo -e "Found ${GREEN}$num_pages${NC} potential pages."

    local ram_mode_active=false
    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        ram_mode_active=true
    fi

    # RAM mode keeps source content only in-process (bash arrays).
    # GNU parallel spawns fresh shells that cannot access those arrays.
    if $ram_mode_active; then
        if [ "$num_pages" -gt 1 ]; then
            echo -e "${YELLOW}Using shell parallel workers for $num_pages RAM-mode pages${NC}"
            local cores
            cores=$(get_parallel_jobs)

            {
                local file quoted_file
                for file in "${page_files[@]}"; do
                    printf -v quoted_file '%q' "$file"
                    echo "process_single_page_file $quoted_file"
                done
            } | run_parallel "$cores"
        else
            echo -e "${YELLOW}Using sequential processing for RAM-mode pages${NC}"
            process_single_page_file "${page_files[0]}"
        fi
    # Use GNU parallel if available, otherwise fallback
    # IMPORTANT: Assumes HAS_PARALLEL is exported/available
    elif [ "${HAS_PARALLEL:-false}" = true ]; then
        echo -e "${GREEN}Using GNU parallel to generate pages${NC}"
        # Determine number of cores
        local cores
        cores=$(get_parallel_jobs)
        
        # Export functions needed by the parallel process and its children
        export -f convert_page process_single_page_file
        # Export necessary dependencies from sourced scripts
        export -f calculate_reading_time file_needs_rebuild convert_markdown_to_html parse_metadata generate_slug
        export -f common_rebuild_check config_has_changed # from cache.sh
        export -f portable_md5sum get_file_mtime format_date fix_url # from utils.sh
        # Export necessary variables for cache checks and template paths
        export OUTPUT_DIR CACHE_DIR TEMPLATES_DIR THEME LOCALE_DIR SITE_LANG FORCE_REBUILD HEADER_TEMPLATE FOOTER_TEMPLATE
        export CONFIG_HASH_FILE # Export path to hash file

        # Process page files in parallel using newline separation
        printf '%s\n' "${page_files[@]}" | parallel --jobs "$cores" --will-cite process_single_page_file {}
    else
        # Fallback to sequential processing
        echo -e "${YELLOW}Using sequential processing for pages${NC}"
        local file
        for file in "${page_files[@]}"; do
            process_single_page_file "$file"
        done
    fi

    echo -e "${GREEN}Static page processing complete!${NC}"
}

# --- Page Generation Functions --- END --- 
