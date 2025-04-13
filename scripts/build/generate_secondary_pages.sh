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
    echo -e "${YELLOW}Generating pages index...${NC}"

    # Access the exported array string and reconstruct the array
    local temp_secondary_pages=()
    # shellcheck disable=SC2206 # Word splitting is intended here
    eval "temp_secondary_pages=($SECONDARY_PAGES)"

    # Skip if there are no secondary pages
    if [ ${#temp_secondary_pages[@]} -eq 0 ]; then
        echo -e "${YELLOW}No secondary pages found, skipping pages index${NC}"
        return 0
    fi

    local pages_index="$OUTPUT_DIR/pages.html"

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
    local tmp_schema=$(mktemp)

    # Create CollectionPage schema
    cat > "$tmp_schema" << EOF
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