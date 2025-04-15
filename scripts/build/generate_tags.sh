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
# Source the feed generator script for the reusable RSS function
# shellcheck source=generate_feeds.sh disable=SC1091
source "$(dirname "$0")/generate_feeds.sh" || { echo >&2 "Error: Failed to source generate_feeds.sh from generate_tags.sh"; exit 1; }

# Generate tag pages
generate_tag_pages() {
    echo -e "${YELLOW}Processing tag pages${NC}${ENABLE_TAG_RSS:+" and RSS feeds"}...${NC}"

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
        echo -e "${GREEN}Tags index, tag pages${NC}${ENABLE_TAG_RSS:+, and tag RSS feeds} appear up to date, skipping.${NC}"
        echo -e "${GREEN}Tag pages processed!${NC}" # Keep consistent final message
        echo -e "${GREEN}Generated tag list pages.${NC}" # Keep consistent final message
        return 0
    fi
    # --- Global Up-to-Date Check --- END ---

    # --- Proceed with Generation (as rebuild is needed) ---

    # Get unique tags (Tag|URL pairs)
    local unique_tags_lines=$(awk -F'|' '{print $1 "|" $2}' "$tags_index_file" | sort | uniq)
    local tag_count=$(echo "$unique_tags_lines" | grep -v '^$' | wc -l)
    echo -e "Checking ${GREEN}$tag_count${NC} tag pages${NC}${ENABLE_TAG_RSS:+/feeds} for changes"

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
            local tag_rss_file="$OUTPUT_DIR/tags/$tag_url/rss.xml"
            local tag_page_rel_url="/tags/${tag_url}/"
            local tag_rss_rel_url="/tags/${tag_url}/rss.xml"
            local rebuild_html=false
            local rebuild_rss=false

            # Check if HTML page needs rebuild
            if parallel_file_needs_rebuild "$tag_page_html_file" "$latest_dep_time"; then
                rebuild_html=true
            fi
            # Check if RSS feed needs rebuild (only if enabled)
            if [ "${ENABLE_TAG_RSS:-false}" = true ]; then
                if parallel_file_needs_rebuild "$tag_rss_file" "$latest_dep_time"; then
                    rebuild_rss=true
                fi
            fi

            # Skip if neither needs rebuilding
            if [ "$rebuild_html" = false ] && [ "$rebuild_rss" = false ]; then
                # echo -e "Skipping unchanged tag: ${YELLOW}$tag${NC}" # Already handled in the main loop
                return 0
            fi

            echo -e "Processing tag: ${GREEN}$tag${NC}" # Print only when generating HTML or RSS
            mkdir -p "$OUTPUT_DIR/tags/$tag_url/" # Create directory if it doesn't exist

            # --- Generate HTML Page (if needed) ---
            if [ "$rebuild_html" = true ]; then
                echo -e "  Generating HTML page..."
                local header_content="$HEADER_TEMPLATE"
                local footer_content="$FOOTER_TEMPLATE"

                # Replace placeholders in the header
                header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
                # Use MSG_ variable for page title
                header_content=${header_content//\{\{page_title\}\}/"${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag"}
                header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
                header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
                header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
                header_content=${header_content//\{\{og_type\}\}/"website"}
                header_content=${header_content//\{\{page_url\}\}/"$tag_page_rel_url"}
                header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
                
                # Add link to tag-specific RSS feed in header (only if enabled)
                if [ "${ENABLE_TAG_RSS:-false}" = true ]; then
                    header_content=${header_content//<!-- bssg:tag_rss_link -->/<link rel="alternate" type="application/rss+xml" title="${SITE_TITLE} - Posts tagged with ${tag}" href="${SITE_URL}${tag_rss_rel_url}">}
                else
                    # Remove placeholder if RSS disabled
                    header_content=${header_content//<!-- bssg:tag_rss_link -->/}
                fi

                # Generate CollectionPage schema for tag pages
                local schema_json_ld=""
                local tmp_schema=$(mktemp)
                
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
                schema_json_ld=$(cat "$tmp_schema")
                rm "$tmp_schema"
                header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

                # Remove image placeholders
                header_content=${header_content//\{\{og_image\}\}/""}
                header_content=${header_content//\{\{twitter_image\}\}/""}

                # Replace placeholders in the footer
                footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
                footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

                # Create the tag page
                cat > "$tag_page_html_file" << EOF
$header_content
<h1>${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag</h1>
<div class="posts-list">
EOF

                # Add posts for this tag - use direct approach for parallel safety
                local temp_file=$(mktemp)
                awk -F'|' -v tag="$tag" -v url="$tag_url" '$1 == tag && $2 == url' "$tags_index_file" > "$temp_file"
                
                if [ -s "$temp_file" ]; then
                    while IFS= read -r post_line; do
                        if [ -z "$post_line" ]; then continue; fi
                        
                        local _ _ title date lastmod filename slug image image_caption description
                        IFS='|' read -r _ _ title date lastmod filename slug image image_caption description <<< "$post_line"
                        
                        # Create slug-based URL path
                        local post_year post_month post_day
                        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                            post_year="${BASH_REMATCH[1]}"
                            post_month=$(awk -v m="${BASH_REMATCH[2]}" 'BEGIN { printf "%02d", m }')
                            post_day=$(awk -v d="${BASH_REMATCH[3]}" 'BEGIN { printf "%02d", d }')
                        else
                            post_year=$(date +%Y); post_month=$(date +%m); post_day=$(date +%d)
                        fi
                        
                        local formatted_path="${URL_SLUG_FORMAT//Year/$post_year}"
                        formatted_path="${formatted_path//Month/$post_month}"
                        formatted_path="${formatted_path//Day/$post_day}"
                        formatted_path="${formatted_path//slug/$slug}"
                        local post_link="/${formatted_path}/"

                        # Format date
                        local display_date_format="$DATE_FORMAT"
                        if [ "${SHOW_TIMEZONE:-false}" = false ]; then
                            display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
                        fi
                        local formatted_date=$(format_date "$date" "$display_date_format")

                        cat >> "$tag_page_html_file" << EOF
    <article>
        <h3><a href="${SITE_URL}${post_link}">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $formatted_date</div>
EOF

                        if [ -n "$image" ]; then
                            local image_url=$(fix_url "$image")
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
                rm "$temp_file"

                # Close the tag page
                cat >> "$tag_page_html_file" << EOF
</div>
<p><a href="${SITE_URL}/tags/">${MSG_ALL_TAGS:-"All Tags"}</a></p>
$footer_content
EOF
                echo -e "  Generated HTML page for: ${GREEN}$tag${NC}"
            # else
            #     echo -e "  HTML page for $tag is up to date."
            fi # End HTML generation

            # --- Generate RSS Feed (if needed and enabled) ---
            if [ "${ENABLE_TAG_RSS:-false}" = true ] && [ "$rebuild_rss" = true ]; then
                echo -e "  Generating RSS feed..."
                local rss_item_limit=${RSS_ITEM_LIMIT:-15}
                local feed_title="${SITE_TITLE} - ${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag"
                local feed_desc="${MSG_POSTS_TAGGED_WITH:-"Posts tagged with"}: $tag"
                local feed_link_rel="$tag_page_rel_url"
                local feed_atom_link_rel="$tag_rss_rel_url"

                # Get post data for this tag from the tags index
                # Sort by post date (field 4), then lastmod (field 5) reverse, limit
                # IMPORTANT: tags_index.txt has format: Tag|TagSlug|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|Image|ImageCaption|PostDescription
                # We need to map this to the format expected by _generate_rss_feed:
                # file|filename|title|date|lastmod|tags|slug|image|image_caption|description
                # We lack the original 'file' path and 'tags' string here. We can approximate.

                local tag_post_data_tmp=$(mktemp)
                awk -F'|' -v tag="$tag" -v url="$tag_url" '$1 == tag && $2 == url {print $0}' "$tags_index_file" | 
                sort -t'|' -k4,4r -k5,5r | 
                head -n "$rss_item_limit" | 
                awk -F'|' -v tag_val="$tag" 'BEGIN {OFS="|"} { 
                    # Reconstruct needed fields. Use filename as proxy for 'file'. Tags will just be the current tag.
                    # file | filename | title | date | lastmod | tags | slug | image | image_caption | description
                    print $6 "|" $6 "|" $3 "|" $4 "|" $5 "|" tag_val "|" $7 "|" $8 "|" $9 "|" $10
                }' > "$tag_post_data_tmp"

                local tag_post_data=$(cat "$tag_post_data_tmp")
                rm "$tag_post_data_tmp"

                # Check if _generate_rss_feed function exists (needed for parallel)
                if ! command -v _generate_rss_feed > /dev/null 2>&1; then
                    echo -e "${RED}Error: _generate_rss_feed function not found. Ensure generate_feeds.sh is sourced correctly.${NC}" >&2
                else
                    # Call the reusable function from generate_feeds.sh
                    # Ensure necessary vars like SITE_URL, SITE_LANG etc. are exported/available
                    _generate_rss_feed "$tag_rss_file" "$feed_title" "$feed_desc" "$feed_link_rel" "$feed_atom_link_rel" "$tag_post_data"
                    echo -e "  Generated RSS feed for: ${GREEN}$tag${NC}"
                fi
            # else
            #     echo -e "  RSS feed for $tag is up to date."
            fi # End RSS generation

        fi # End check for non-empty tag
    } # End process_tag function

    # Process tags either in parallel or sequentially
    local tags_to_process_list=()
    local skipped_tag_count=0
    local force_rebuild_status="${FORCE_REBUILD:-false}"

    # Loop through lines using process substitution
    while IFS= read -r tag_line; do
        if [ -z "$tag_line" ]; then continue; fi
        local tag tag_url
        IFS='|' read -r tag tag_url <<< "$tag_line"
        local tag_page_html_file="$OUTPUT_DIR/tags/$tag_url/index.html"
        local tag_rss_file="$OUTPUT_DIR/tags/$tag_url/rss.xml"

        # Check if *either* HTML or RSS (if enabled) needs rebuild
        if [ "$force_rebuild_status" = true ] || \
           parallel_file_needs_rebuild "$tag_page_html_file" "$latest_dependency_time" || \
           ( [ "${ENABLE_TAG_RSS:-false}" = true ] && parallel_file_needs_rebuild "$tag_rss_file" "$latest_dependency_time" ); then
             tags_to_process_list+=("$tag_line")
        else
             echo -e "Skipping unchanged tag (HTML${NC}${ENABLE_TAG_RSS:+ & RSS}): ${YELLOW}$tag${NC}"
             skipped_tag_count=$((skipped_tag_count + 1))
        fi
    done < <(echo "$unique_tags_lines")

    local tags_to_process_count=${#tags_to_process_list[@]}

    if [ $tags_to_process_count -gt 0 ]; then
        echo -e "Found ${GREEN}$tags_to_process_count${NC} tags needing processing (HTML${NC}${ENABLE_TAG_RSS:+ or RSS}) (Skipped: $skipped_tag_count).${NC}"
        if [ "${HAS_PARALLEL:-false}" = true ]; then
            echo -e "${GREEN}Using GNU parallel to process tag pages${NC}${ENABLE_TAG_RSS:+/feeds}"
            local cores=1
            if command -v nproc > /dev/null 2>&1; then cores=$(nproc);
            elif command -v sysctl > /dev/null 2>&1; then cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1); fi

            # Export necessary functions and variables
            # Dependencies for process_tag HTML part
            export -f process_tag parallel_file_needs_rebuild get_file_mtime fix_url format_date
            export OUTPUT_DIR CACHE_DIR SITE_URL SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME
            export HEADER_TEMPLATE FOOTER_TEMPLATE DATE_FORMAT TIMEZONE SHOW_TIMEZONE URL_SLUG_FORMAT
            export MSG_TAG_PAGE_TITLE MSG_PUBLISHED_ON MSG_BY MSG_READ_MORE MSG_ALL_TAGS
            # Dependencies for process_tag RSS part (via _generate_rss_feed)
            # Only export these if tag RSS is enabled
            if [ "${ENABLE_TAG_RSS:-false}" = true ]; then
                export -f _generate_rss_feed convert_markdown_to_html # From generate_feeds.sh & content.sh
                export MD5_CMD CACHE_DIR MARKDOWN_PROCESSOR MARKDOWN_PL_PATH RSS_INCLUDE_FULL_CONTENT # From deps/config
                export SITE_LANG RSS_ITEM_LIMIT MSG_POSTS_TAGGED_WITH # From config/locale
            fi
            # Pass index path and latest time
            export tags_index_file latest_dependency_time

            printf "%s\n" "${tags_to_process_list[@]}" | parallel --jobs "$cores" process_tag {} "$tags_index_file" "$latest_dependency_time" || { echo -e "${RED}Parallel tag processing failed.${NC}"; exit 1; }

        else
            echo -e "${YELLOW}Using sequential processing for $tags_to_process_count tags${NC}"
            local tag_line
            for tag_line in "${tags_to_process_list[@]}"; do
                process_tag "$tag_line" "$tags_index_file" "$latest_dependency_time"
            done
        fi
    else
         echo -e "${GREEN}All $tag_count individual tag pages${NC}${ENABLE_TAG_RSS:+ and RSS feeds} are up to date.${NC}"
    fi

    # --- Generate the main tags index page (tags/index.html) --- START ---
    echo -e "Generating tags/index.html"
    local main_tags_index_rebuild_needed=false
    # Re-check if main index needs rebuild based *only* on latest_dependency_time now
    # We already know from the global check that *something* requires a rebuild

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
        header_content=${header_content//\{\{og_type\}\}/"website"}
        local tag_index_rel_url="/tags/"
        header_content=${header_content//\{\{page_url\}\}/"$tag_index_rel_url"}
        header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
        
        # Remove the placeholder for the tag-specific RSS feed link in the main tags index
        header_content=${header_content//<!-- bssg:tag_rss_link -->/}

        # Generate CollectionPage schema for tags index
        local schema_json_ld=""
        local tmp_schema=$(mktemp)
        
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
        schema_json_ld=$(cat "$tmp_schema")
        rm "$tmp_schema"
        header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}
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

        # Add all tags to the index page
        echo "$unique_tags_lines" | while read -r tag_line; do
            local tag tag_url
            IFS='|' read -r tag tag_url <<< "$tag_line"

            if [ -n "$tag" ]; then
                local post_count=0
                if [ -f "$tags_index_file" ] && [ -s "$tags_index_file" ]; then
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