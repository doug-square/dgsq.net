#!/usr/bin/env bash
#
# BSSG - Tag Page Generation
# Handles the creation of individual tag pages and the main tag index.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_tags.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_tags.sh"; exit 1; }

# Generate tag pages
generate_tag_pages() {
    echo -e "${YELLOW}Processing tag pages...${NC}"

    local tags_index_file="$CACHE_DIR/tags_index.txt"
    local main_tags_index_output="$OUTPUT_DIR/tags/index.html"

    # Check if the tags index file exists
    if [ ! -f "$tags_index_file" ]; then
        echo -e "${RED}Error: Tags index file not found at $tags_index_file${NC}"
        return 1
    fi

    # --- Global Up-to-Date Check --- START ---
    # IMPORTANT: Requires common_rebuild_check, get_file_mtime to be available
    #            Requires BSSG_CONFIG_CHANGED_STATUS to be exported by main.sh

    # Check common dependencies (config, templates, locale) using the main output file
    common_rebuild_check "$main_tags_index_output"
    local common_result=$?
    local needs_rebuild=false
    local latest_dependency_time=0

    if [ $common_result -eq 0 ]; then
        needs_rebuild=true # Common checks failed
    else # common_result is 2 (output exists and newer than common deps)
        # Get mtime of the output file (which is newer than templates/locale)
        latest_dependency_time=$(get_file_mtime "$main_tags_index_output")

        # Get mtime of the tags index file
        local tags_index_time=$(get_file_mtime "$tags_index_file")

        # Compare tags index time with the output time
        if (( tags_index_time > latest_dependency_time )); then
            needs_rebuild=true # Tags index is newer than the main tags output page
            latest_dependency_time=$tags_index_time # Update latest time for individual checks
        fi
    fi

    # If no rebuild needed based on common checks and tags_index.txt mtime vs main output
    if [ "$needs_rebuild" = false ]; then
        echo -e "${GREEN}Tags index and tag pages appear up to date, skipping.${NC}"
        echo -e "${GREEN}Tag pages processed!${NC}" # Keep consistent final message
        echo -e "${GREEN}Generated tag list pages.${NC}" # Keep consistent final message
        return 0
    fi
    # --- Global Up-to-Date Check --- END ---

    # --- Proceed with Generation (as rebuild is needed) ---

    # Get unique tags (Tag|URL pairs)
    local unique_tags_lines=$(awk -F'|' '{print $1 "|" $2}' "$tags_index_file" | sort | uniq)
    local tag_count=$(echo "$unique_tags_lines" | grep -v '^$' | wc -l)
    echo -e "Checking ${GREEN}$tag_count${NC} tag pages for changes"

    # Define a modified file_needs_rebuild function for parallel use - Now simpler
    # This version only checks if the specific tag output file is older than the
    # latest dependency time calculated during the global check.
    # No need to re-check common deps or tags_index time here.
    parallel_file_needs_rebuild() {
        local output_file="$1"
        local latest_dep_time="$2"

        # Rebuild if output file doesn't exist
        if [ ! -f "$output_file" ]; then
            return 0 # Rebuild needed
        fi
        
        local output_time=$(get_file_mtime "$output_file")
        
        # Rebuild if output is older than the latest relevant dependency
        if (( output_time < latest_dep_time )); then
            return 0 # Rebuild needed
        fi
        
        return 1 # No rebuild needed
    }

    # Define a function to process a single tag
    process_tag() {
        local tag_line="$1"
        local tags_index_file="$2" # Still needed to find posts for the tag
        local latest_dep_time="$3" # Pass the calculated latest dependency time
        local tag tag_url
        IFS='|' read -r tag tag_url <<< "$tag_line"

        if [ -n "$tag" ]; then
            local tag_page_html_file="$OUTPUT_DIR/tags/$tag_url/index.html"

            echo -e "Generating tag page for: ${GREEN}$tag${NC}" # Print only when generating

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
            
            # Set proper URL in og:url and ensure trailing slash
            local tag_page_rel_url="/tags/${tag_url}/"
            header_content=${header_content//\{\{page_url\}\}/"$tag_page_rel_url"}
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
  "url": "$SITE_URL${tag_page_rel_url}",
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
            mkdir -p "$OUTPUT_DIR/tags/$tag_url/" # Create directory
            cat > "$tag_page_html_file" << EOF
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
                    
                    local _ _ title date lastmod filename slug image image_caption description
                    IFS='|' read -r _ _ title date lastmod filename slug image image_caption description <<< "$post_line"
                    
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

                    # Ensure the link uses a trailing slash
                    local post_link="/${formatted_path}/"

                    # Format date based on SHOW_TIMEZONE
                    local display_date_format="$DATE_FORMAT"
                    if [ "${SHOW_TIMEZONE:-false}" = false ]; then
                        # Remove timezone format specifiers (%z or %Z) if they exist
                        display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
                    fi
                    local formatted_date=$(format_date "$date" "$display_date_format")

                    cat >> "$tag_page_html_file" << EOF
    <article>
        <h3><a href="${SITE_URL}${post_link}">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $formatted_date</div>
EOF

                    # Add featured image if specified
                    if [ -n "$image" ]; then
                        # Process image URL to add SITE_URL if it's a relative path
                        local image_url
                        image_url=$(fix_url "$image") # Use fix_url
                        
                        # Use title as fallback for alt text if caption is missing
                        local alt_text="${image_caption:-$title}"
                        local figcaption_content="${image_caption:-$title}"

                        cat >> "$tag_page_html_file" << EOF
        <figure class="featured-image tag-image">
            <a href="${SITE_URL}${post_link}">
                <img src="$image_url" alt="$alt_text" /> 
            </a>
            <figcaption>$figcaption_content</figcaption>
        </figure>
EOF
                    fi
                    
                    
                    # Add description/excerpt if available
                    if [ -n "$description" ]; then
                        cat >> "$tag_page_html_file" << EOF
        <div class="summary">
            <p>$description</p>
        </div>
EOF
                    fi

                    cat >> "$tag_page_html_file" << EOF
    </article>
EOF
                done < "$temp_file"
            fi
            rm "$temp_file" # Clean up temp file

            # Close the tag page
            cat >> "$tag_page_html_file" << EOF
</div>
<p><a href="${SITE_URL}/tags/">${MSG_ALL_TAGS:-"All Tags"}</a></p>
$footer_content
EOF
            echo -e "Generated tag page for: ${GREEN}$tag${NC}"
        fi
    }

    # Process tags either in parallel or sequentially
    local tags_to_process_list=()
    local skipped_tag_count=0
    local force_rebuild_status="${FORCE_REBUILD:-false}"

    # Loop through lines using process substitution (avoids subshell for the loop body)
    while IFS= read -r tag_line; do
        if [ -z "$tag_line" ]; then continue; fi # Should be redundant now, but safe
        local tag tag_url
        IFS='|' read -r tag tag_url <<< "$tag_line"
        local tag_page_html_file="$OUTPUT_DIR/tags/$tag_url/index.html"

        # Check if rebuild needed: either force flag is true OR the mtime check passes
        if [ "$force_rebuild_status" = true ] || parallel_file_needs_rebuild "$tag_page_html_file" "$latest_dependency_time"; then
             tags_to_process_list+=("$tag_line")
        else
             echo -e "Skipping unchanged tag: ${YELLOW}$tag${NC}"
             skipped_tag_count=$((skipped_tag_count + 1))
        fi
    done < <(echo "$unique_tags_lines") # Use process substitution here

    local tags_to_process_count=${#tags_to_process_list[@]}

    if [ $tags_to_process_count -gt 0 ]; then
        echo -e "Found ${GREEN}$tags_to_process_count${NC} tag pages needing processing (Skipped: $skipped_tag_count)."
        if [ "${HAS_PARALLEL:-false}" = true ]; then
            echo -e "${GREEN}Using GNU parallel to process tag pages${NC}"
            local cores=1
            if command -v nproc > /dev/null 2>&1; then cores=$(nproc);
            elif command -v sysctl > /dev/null 2>&1; then cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1); fi

            # Export necessary functions and variables
            export -f process_tag parallel_file_needs_rebuild
            # Export dependencies for process_tag
            export -f get_file_mtime fix_url format_date # From utils.sh
            export OUTPUT_DIR CACHE_DIR SITE_URL SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME
            export HEADER_TEMPLATE FOOTER_TEMPLATE DATE_FORMAT TIMEZONE SHOW_TIMEZONE URL_SLUG_FORMAT
            export MSG_TAG_PAGE_TITLE MSG_PUBLISHED_ON MSG_BY MSG_READ_MORE MSG_ALL_TAGS # Locale messages
            export tags_index_file latest_dependency_time # Pass index path and latest time

            printf "%s\n" "${tags_to_process_list[@]}" | parallel --jobs "$cores" process_tag {} "$tags_index_file" "$latest_dependency_time" || { echo -e "${RED}Parallel tag processing failed.${NC}"; exit 1; }

        else
            echo -e "${YELLOW}Using sequential processing for $tags_to_process_count tag pages${NC}"
            local tag_line
            for tag_line in "${tags_to_process_list[@]}"; do
                process_tag "$tag_line" "$tags_index_file" "$latest_dependency_time"
            done
        fi
    else
         echo -e "${GREEN}All $tag_count individual tag pages are up to date.${NC}"
    fi

    # --- Generate the main tags index page (tags/index.html) --- START ---
    echo -e "Generating tags/index.html"
    local main_tags_index_rebuild_needed=false
    # Re-check if main index needs rebuild based *only* on latest_dependency_time now
    # We already know from the global check that *something* requires a rebuild (either
    # common deps, tags_index.txt, or an individual tag page was older)

    # Force rebuild takes precedence
    if [ "$force_rebuild_status" = true ]; then
        main_tags_index_rebuild_needed=true
        echo -e "${YELLOW}Force rebuild enabled for tags/index.html${NC}"
    elif [ ! -f "$main_tags_index_output" ]; then
        main_tags_index_rebuild_needed=true
    else
        local main_output_time=$(get_file_mtime "$main_tags_index_output")
        if (( main_output_time < latest_dependency_time )); then
             main_tags_index_rebuild_needed=true
        fi
    fi

    if [ "$main_tags_index_rebuild_needed" = true ]; then
        local header_content="$HEADER_TEMPLATE"
        local footer_content="$FOOTER_TEMPLATE"

        # Replace placeholders in the header
        header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
        header_content=${header_content//\{\{page_title\}\}/"${MSG_ALL_TAGS:-"All Tags"}"} # Use MSG var
        header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
        
        # Set og:type to website for tags index
        header_content=${header_content//\{\{og_type\}\}/"website"}
        
        # Set proper URL in og:url
        local tag_index_rel_url="/tags/"
        header_content=${header_content//\{\{page_url\}\}/"$tag_index_rel_url"}
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
  "name": "${MSG_ALL_TAGS:-"All Tags"}",
  "description": "List of all tags on $SITE_TITLE",
  "url": "$SITE_URL${tag_index_rel_url}",
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
        mkdir -p "$(dirname "$main_tags_index_output")"
        cat > "$main_tags_index_output" << EOF
$header_content
<h1>${MSG_ALL_TAGS:-"All Tags"}</h1>
<div class="tags-list">
EOF

        # Add all tags to the index page - prevent grep errors with empty files
        echo "$unique_tags_lines" | while read -r tag_line; do
            local tag tag_url
            IFS='|' read -r tag tag_url <<< "$tag_line"

            if [ -n "$tag" ]; then
                # Count posts with this tag, but prevent errors with empty files
                local post_count=0
                if [ -f "$tags_index_file" ] && [ -s "$tags_index_file" ]; then
                    # Ensure the grep pattern is properly quoted and escaped
                    # We use awk for safer field extraction
                    post_count=$(awk -F'|' -v tag="$tag" -v url="$tag_url" '$1 == tag && $2 == url { count++ } END { print count }' "$tags_index_file" 2>/dev/null || echo 0)
                fi

                # Ensure link to individual tag page has trailing slash
                cat >> "$main_tags_index_output" << EOF
    <a href="${SITE_URL}/tags/$tag_url/">$tag <span class="tag-count">($post_count)</span></a>
EOF
            fi
        done

        # Close the tags index page
        cat >> "$main_tags_index_output" << EOF
</div>
$footer_content
EOF
      echo -e "Generated ${GREEN}tags/index.html${NC}"
    else
        echo -e "Skipping unchanged tags index"
    fi
    # --- Generate the main tags index page --- END ---

    echo -e "${GREEN}Tag pages processed!${NC}"
}

# Export the main function for the build script
export -f generate_tag_pages 