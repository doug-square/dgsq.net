#!/usr/bin/env bash
#
# BSSG - Secondary Pages Index Generation
# Creates pages.html listing all secondary (non-post, non-primary) pages.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_secondary_pages.sh"; exit 1; }
# Note: Needs access to SECONDARY_PAGES array exported by templates.sh

# Generate pages index
generate_pages_index() {
    # --- Define Target File --- 
    local pages_index="$OUTPUT_DIR/pages.html"
    local secondary_pages_list_file="${CACHE_DIR:-.bssg_cache}/secondary_pages.list"
    local ram_mode_active=false
    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        ram_mode_active=true
    fi

    # --- Cache Check --- START ---
    # Rebuild if force flag is set OR if list file exists and output is older than list file
    # OR if list file doesn't exist (implies it was just created or cleaned)
    local should_rebuild=false
    if [[ "${FORCE_REBUILD:-false}" == true ]]; then
        should_rebuild=true
        echo -e "${YELLOW}Forcing pages index rebuild (--force-rebuild).${NC}"
    elif ! $ram_mode_active && [ ! -f "$secondary_pages_list_file" ]; then
         # If list file doesn't exist, we need to generate pages.html (or handle absence)
         # This case might mean 0 secondary pages after a clean build.
         # Let the existing logic handle the case of 0 pages later.
         should_rebuild=true 
         echo -e "${YELLOW}Secondary pages list file not found, rebuilding pages index.${NC}"
    elif ! $ram_mode_active && { [ ! -f "$pages_index" ] || [ "$pages_index" -ot "$secondary_pages_list_file" ]; }; then
        should_rebuild=true
        echo -e "${YELLOW}Pages index is older than secondary pages list, rebuilding.${NC}"
    # Add checks for template file changes? More complex, rely on overall rebuild for now.
    # Consider adding checks against header/footer template files if more granularity is needed.
    # Example: || [ "$pages_index" -ot "path/to/header.html" ] ...
    fi
    
    if [[ "$should_rebuild" == false ]]; then
        echo -e "${GREEN}Pages index '$pages_index' is up to date, skipping.${NC}"
        return 0
    fi
    # --- Cache Check --- END ---
    
    echo -e "${YELLOW}Generating pages index...${NC}"

    # --- Read secondary pages from cache file --- START ---
    local temp_secondary_pages=()
    
    if $ram_mode_active; then
        mapfile -t temp_secondary_pages < <(printf '%s\n' "$(ram_mode_get_dataset "secondary_pages")" | awk 'NF')
    elif [ -f "$secondary_pages_list_file" ]; then
        # Use mapfile (readarray) to read lines into the array
        mapfile -t temp_secondary_pages < "$secondary_pages_list_file"
        # Optional: Trim whitespace from each element if necessary (mapfile usually handles newlines)
        # for i in "${!temp_secondary_pages[@]}"; do
        #     temp_secondary_pages[$i]=$(echo "${temp_secondary_pages[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # done
    else
        echo -e "${YELLOW}Cache file '$secondary_pages_list_file' not found. Assuming no secondary pages.${NC}"
    fi
    # --- Read secondary pages from cache file --- END ---

    # Skip if there are no secondary pages
    if [ ${#temp_secondary_pages[@]} -eq 0 ]; then
        echo -e "${YELLOW}No secondary pages found, skipping pages index${NC}"
        return 0
    fi

    # Prepare templates (should be exported already)
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"

    # Replace placeholders in the header
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    # Use MSG_ var for title
    header_content=${header_content//\{\{page_title\}\}/"${MSG_ALL_PAGES:-"All Pages"}"}
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
    # Create CollectionPage schema
    schema_json_ld=$(cat << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "${MSG_ALL_PAGES:-"All Pages"}",
  "description": "$SITE_DESCRIPTION",
  "url": "$(fix_url "/pages.html")",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
)

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
<h1>${MSG_ALL_PAGES:-"All Pages"}</h1>
<div class="posts-list">
EOF

    # Add all secondary pages to the index (using the reconstructed array)
    for page in "${temp_secondary_pages[@]}"; do
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

# Make function available for sourcing
export -f generate_pages_index 
