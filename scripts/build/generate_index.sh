#!/usr/bin/env bash
#
# BSSG - Index/Pagination Generation
# Handles the creation of the main index.html and paginated index pages.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_index.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_index.sh"; exit 1; }

_generate_index_ram() {
    echo -e "${YELLOW}Generating index pages...${NC}"

    local file_index_data
    file_index_data=$(ram_mode_get_dataset "file_index")
    if [ -z "$file_index_data" ]; then
        echo -e "${YELLOW}No posts found in RAM file index. Skipping index generation.${NC}"
        return 0
    fi

    local total_posts_orig
    total_posts_orig=$(printf '%s\n' "$file_index_data" | awk 'NF { c++ } END { print c+0 }')
    local total_pages=$(( (total_posts_orig + POSTS_PER_PAGE - 1) / POSTS_PER_PAGE ))
    [ "$total_pages" -eq 0 ] && total_pages=1

    mapfile -t file_index_lines < <(printf '%s\n' "$file_index_data" | awk 'NF')
    echo -e "Generating ${GREEN}$total_pages${NC} index pages for ${GREEN}$total_posts_orig${NC} posts"

    local current_page
    for (( current_page = 1; current_page <= total_pages; current_page++ )); do
        local output_file
        if [ "$current_page" -eq 1 ]; then
            output_file="$OUTPUT_DIR/index.html"
        else
            output_file="$OUTPUT_DIR/page/$current_page/index.html"
            mkdir -p "$(dirname "$output_file")"
        fi

        local page_header="$HEADER_TEMPLATE"
        if [ "$current_page" -eq 1 ]; then
            page_header=${page_header//\{\{site_title\}\}/"$SITE_TITLE"}
            page_header=${page_header//\{\{page_title\}\}/"${MSG_HOME:-"Home"}"}
            page_header=${page_header//\{\{og_type\}\}/"website"}
            page_header=${page_header//\{\{page_url\}\}/""}
            page_header=${page_header//\{\{site_url\}\}/"$SITE_URL"}
            local home_schema
            home_schema=$(cat <<EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "name": "$SITE_TITLE",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL/",
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
)
            page_header=${page_header//\{\{schema_json_ld\}\}/"$home_schema"}
        else
            local pag_title
            pag_title=$(printf "${MSG_PAGINATION_TITLE:-"%s - Page %d"}" "$SITE_TITLE" "$current_page")
            page_header=${page_header//\{\{site_title\}\}/"$SITE_TITLE"}
            page_header=${page_header//\{\{page_title\}\}/"$pag_title"}
            page_header=${page_header//\{\{og_type\}\}/"website"}
            local paginated_rel_url="/page/$current_page/"
            page_header=${page_header//\{\{page_url\}\}/"$paginated_rel_url"}
            page_header=${page_header//\{\{site_url\}\}/"$SITE_URL"}
            local collection_schema
            collection_schema=$(cat <<EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "$pag_title",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL${paginated_rel_url}",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
)
            page_header=${page_header//\{\{schema_json_ld\}\}/"$collection_schema"}
        fi
        page_header=${page_header//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{og_image\}\}/""}
        page_header=${page_header//\{\{twitter_image\}\}/""}

        local page_footer="$FOOTER_TEMPLATE"
        page_footer=${page_footer//\{\{current_year\}\}/$(date +%Y)}
        page_footer=${page_footer//\{\{author_name\}\}/"$AUTHOR_NAME"}

        cat > "$output_file" <<EOF
$page_header
EOF

        local index_file="${PAGES_DIR}/index.md"
        local has_custom_index=false
        if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$index_file"; then
            has_custom_index=true
        elif [ -f "$index_file" ]; then
            has_custom_index=true
        fi

        if [ "$current_page" -eq 1 ] && [ "$has_custom_index" = true ]; then
            local content="" html_content="" in_frontmatter=false found_frontmatter=false source_stream=""
            if [ "${BSSG_RAM_MODE:-false}" = true ] && ram_mode_has_file "$index_file"; then
                source_stream=$(ram_mode_get_content "$index_file")
            else
                source_stream=$(cat "$index_file")
            fi
            while IFS= read -r line; do
                if [[ "$line" == "---" ]]; then
                    if ! $in_frontmatter && ! $found_frontmatter; then
                        in_frontmatter=true
                        found_frontmatter=true
                        continue
                    elif $in_frontmatter; then
                        in_frontmatter=false
                        continue
                    fi
                fi
                if ! $in_frontmatter && $found_frontmatter; then
                    content+="$line"$'\n'
                fi
            done <<< "$source_stream"
            if ! $found_frontmatter; then
                content="$source_stream"
            fi
            html_content=$(convert_markdown_to_html "$content")
            echo "$html_content" >> "$output_file"
            cat >> "$output_file" <<EOF
$page_footer
EOF
            continue
        fi

        if [ "$total_posts_orig" -gt 0 ]; then
            cat >> "$output_file" <<EOF
<h1>${MSG_LATEST_POSTS:-"Latest Posts"}</h1>
<div class="posts-list">
EOF
            local start_index=$(( (current_page - 1) * POSTS_PER_PAGE ))
            local end_index=$(( start_index + POSTS_PER_PAGE - 1 ))
            local i
            for (( i = start_index; i <= end_index && i < total_posts_orig; i++ )); do
                local file filename title date lastmod tags slug image image_caption description author_name author_email
                IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email <<< "${file_index_lines[$i]}"
                [ -z "$file" ] && continue
                [ -z "$title" ] && continue
                [ -z "$date" ] && continue

                local post_year post_month post_day
                if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                    post_year="${BASH_REMATCH[1]}"
                    post_month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                    post_day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
                else
                    post_year=$(date +%Y); post_month=$(date +%m); post_day=$(date +%d)
                fi
                local formatted_path="${URL_SLUG_FORMAT//Year/$post_year}"
                formatted_path="${formatted_path//Month/$post_month}"
                formatted_path="${formatted_path//Day/$post_day}"
                formatted_path="${formatted_path//slug/$slug}"
                local post_link="/$formatted_path/"

                local display_date_format="$DATE_FORMAT"
                if [ "${SHOW_TIMEZONE:-false}" = false ]; then
                    display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
                fi
                local formatted_date
                formatted_date=$(format_date "$date" "$display_date_format")

                cat >> "$output_file" <<EOF
    <article>
        <h3><a href="$(fix_url "$post_link")">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $formatted_date${author_name:+" ${MSG_BY:-"by"} ${author_name:-$AUTHOR_NAME}"}</div>
EOF

                if [ -n "$image" ]; then
                    local image_url="$image"
                    if [[ "$image" == /* ]]; then
                        image_url="${SITE_URL}${image}"
                    fi
                    cat >> "$output_file" <<EOF
        <div class="featured-image index-image">
            <a href="$(fix_url "$post_link")">
                <img src="$image_url" alt="${image_caption:-$title}" title="${image_caption:-$title}" />
            </a>
        </div>
EOF
                fi

                if [ "${INDEX_SHOW_FULL_CONTENT:-false}" = "true" ]; then
                    local post_content="" html_content=""
                    if [ "${BSSG_RAM_MODE:-false}" = true ] && ram_mode_has_file "$file"; then
                        local source_stream
                        source_stream=$(ram_mode_get_content "$file")
                        post_content=$(printf '%s\n' "$source_stream" | awk '
                            BEGIN { in_fm = 0; found_fm = 0; }
                            /^---$/ {
                                if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
                                if (in_fm) { in_fm = 0; next; }
                            }
                            { if (!in_fm) print; }
                        ')
                    fi
                    if [ -n "$post_content" ]; then
                        if [[ "$file" == *.md ]]; then
                            html_content=$(convert_markdown_to_html "$post_content")
                        else
                            html_content="$post_content"
                        fi
                    fi
                    if [ -n "$html_content" ]; then
                        cat >> "$output_file" <<EOF
        <div class="post-content">
            $html_content
        </div>
EOF
                    fi
                elif [ -n "$description" ]; then
                    cat >> "$output_file" <<EOF
        <div class="summary">
            $description
        </div>
EOF
                fi

                cat >> "$output_file" <<EOF

    </article>
EOF
            done

            cat >> "$output_file" <<EOF
</div> <!-- .posts-list -->
EOF

            if [ "$total_pages" -gt 1 ]; then
                cat >> "$output_file" <<EOF

<!-- Pagination -->
<div class="pagination">
EOF
                if [ "$current_page" -gt 1 ]; then
                    local prev_page=$((current_page - 1))
                    local prev_url="/"
                    if [ $prev_page -ne 1 ]; then
                        prev_url="/page/$prev_page/"
                    fi
                    cat >> "$output_file" <<PAG_EOF
    <a href="$(fix_url "$prev_url")" class="prev">&laquo; ${MSG_NEWER_POSTS:-Newer}</a>
PAG_EOF
                fi
                cat >> "$output_file" <<PAG_EOF
    <span class="page-info">$(printf "${MSG_PAGE_INFO_TEMPLATE:-Page %d of %d}" "$current_page" "$total_pages")</span>
PAG_EOF
                if [ "$current_page" -lt "$total_pages" ]; then
                    local next_page=$((current_page + 1))
                    cat >> "$output_file" <<PAG_EOF
    <a href="$(fix_url "/page/$next_page/")" class="next">${MSG_OLDER_POSTS:-Older} &raquo;</a>
PAG_EOF
                fi
                cat >> "$output_file" <<EOF
</div>
EOF
            fi
        fi

        cat >> "$output_file" <<EOF
$page_footer
EOF
    done

    echo -e "${GREEN}Index pages processed!${NC}"
}

# Generate main index page (homepage) and paginated pages
generate_index() {
    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        _generate_index_ram
        return $?
    fi

    echo -e "${YELLOW}Generating index pages...${NC}"
    
    # Check if rebuild is needed (using function from cache.sh)
    if ! indexes_need_rebuild; then
        echo -e "${GREEN}Index pages are up to date, skipping...${NC}"
        return
    fi
    
    # Define the index page paths
    local file_index="$CACHE_DIR/file_index.txt"
    
    # Check if file index exists
    if [ ! -f "$file_index" ]; then
      echo -e "${RED}Error: File index $file_index not found. Cannot generate index pages.${NC}"
      return 1
    fi
    
    # Count total posts
    local total_posts_orig=$(wc -l < "$file_index")
    local total_posts=$total_posts_orig
    local total_pages=$(( (total_posts + POSTS_PER_PAGE - 1) / POSTS_PER_PAGE ))
    
    # Ensure total_pages is at least 1 even if total_posts is 0
    if [ $total_pages -eq 0 ]; then
        total_pages=1
    fi
    
    echo -e "Generating ${GREEN}$total_pages${NC} index pages for ${GREEN}$total_posts${NC} posts"
    
    # Prepare templates (already exported, but good to have locally)
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"
    
    # Define function to process a single index page
    process_index_page() {
        # Ensure current_page is treated as an integer
        local -i current_page="$1"
        local -i total_pages="$2"
        local file_index="$3"
        local -i total_posts_orig="$4"
        # Template content is accessed via exported global variables
        
        local output_file
        if [ "$current_page" -eq 1 ]; then
            output_file="$OUTPUT_DIR/index.html"
        else
            output_file="$OUTPUT_DIR/page/$current_page/index.html"
            mkdir -p "$(dirname "$output_file")"
        fi
        
        # Skip if index page file is up to date relative to file index
        if ! file_needs_rebuild "$file_index" "$output_file"; then
            echo -e "Skipping unchanged index page $current_page"
            return 0
        fi
        
        # Replace placeholders in the header
        local page_header="$HEADER_TEMPLATE"
        page_header=${page_header//\{\{site_title\}\}/"$SITE_TITLE"}
        if [ $current_page -eq 1 ]; then
            # For the homepage
            page_header=${page_header//\{\{page_title\}\}/"${MSG_HOME:-"Home"}"}
            page_header=${page_header//\{\{og_type\}\}/"website"}
            page_header=${page_header//\{\{page_url\}\}/""}
            page_header=${page_header//\{\{site_url\}\}/"$SITE_URL"}
            
            # Create WebSite schema for homepage
            local home_url="${SITE_URL}/"
            local schema_json_ld=""
            local tmp_schema=$(mktemp)
            cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "name": "$SITE_TITLE",
  "description": "$SITE_DESCRIPTION",
  "url": "$home_url",
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
            schema_json_ld=$(cat "$tmp_schema")
            rm "$tmp_schema"
            page_header=${page_header//\{\{schema_json_ld\}\}/"$schema_json_ld"}
        else
            # For pagination pages
            local pag_title=$(printf "${MSG_PAGINATION_TITLE:-"%s - Page %d"}" "$SITE_TITLE" "$current_page")
            page_header=${page_header//\{\{page_title\}\}/"$pag_title"}
            page_header=${page_header//\{\{og_type\}\}/"website"}
            local paginated_rel_url="/page/$current_page/"
            page_header=${page_header//\{\{page_url\}\}/"$paginated_rel_url"}
            page_header=${page_header//\{\{site_url\}\}/"$SITE_URL"}
            
            # Create CollectionPage schema for paginated pages
            local schema_json_ld=""
            local tmp_schema=$(mktemp)
            cat > "$tmp_schema" << EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "$pag_title",
  "description": "$SITE_DESCRIPTION",
  "url": "$SITE_URL${paginated_rel_url}",
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
            page_header=${page_header//\{\{schema_json_ld\}\}/"$schema_json_ld"}
        fi
        page_header=${page_header//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
        page_header=${page_header//\{\{og_image\}\}/""}
        page_header=${page_header//\{\{twitter_image\}\}/""}
        
        # Replace placeholders in the footer
        local page_footer="$FOOTER_TEMPLATE"
        page_footer=${page_footer//\{\{current_year\}\}/$(date +%Y)}
        page_footer=${page_footer//\{\{author_name\}\}/"$AUTHOR_NAME"}
        
        # Create the index page
        cat > "$output_file" << EOF
$page_header
EOF

        # If there is an index.md, use that
        if [ -f "${PAGES_DIR}/index.md" ]; then
            local input_file="${PAGES_DIR}/index.md"
            local title=$(parse_metadata "$input_file" "title")
            local start_line=$(grep -n "^---$" "$input_file" | head -1 | cut -d: -f1)
            local end_line=$(grep -n "^---$" "$input_file" | head -2 | tail -1 | cut -d: -f1)

            # Extract content after the second --- line
            content=$(tail -n +$((end_line + 1)) $input_file)

            html_content=$(convert_markdown_to_html "$content")
            echo "$html_content" >> $output_file

            echo -e "${GREEN}Used custom index.md with title '$title' as the sole homepage content.${NC}"

            # Append footer and finish for the homepage
            cat >> "$output_file" << EOF
$page_footer
EOF
            # echo -e "Generated custom index page ${GREEN}$current_page${NC}" # Optional: Specific message
            return 0 # Successfully generated custom index page, skip post listing
        else
            # No index.md found, proceed with standard "Latest Posts" logic
            
            # Only add "Latest Posts" section if there are actually posts
            if [ "$total_posts_orig" -gt 0 ]; then
                cat >> "$output_file" << EOF
<h1>${MSG_LATEST_POSTS:-"Latest Posts"}</h1>
<div class="posts-list">
EOF
            
                # Calculate start and end indices
                local start_index=$(( (current_page - 1) * POSTS_PER_PAGE + 1 ))
                local end_index=$(( current_page * POSTS_PER_PAGE ))
                
                # Add posts to the index page
                awk -v start="$start_index" -v end="$end_index" 'NR >= start && NR <= end { print }' "$file_index" | while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
                    # ... (rest of the post item generation logic remains the same) ...
                    if [ -z "$file" ] || [ -z "$title" ] || [ -z "$date" ]; then
                        continue
                    fi
                    local post_year post_month post_day
                    if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                        post_year="${BASH_REMATCH[1]}"
                        post_month=$(awk -v m="$((10#${BASH_REMATCH[2]}))" 'BEGIN { printf "%02d", m }')
                        post_day=$(awk -v d="$((10#${BASH_REMATCH[3]}))" 'BEGIN { printf "%02d", d }')
                    else
                        post_year=$(date +%Y); post_month=$(date +%m); post_day=$(date +%d)
                    fi
                    local formatted_path="${URL_SLUG_FORMAT//Year/$post_year}"
                    formatted_path="${formatted_path//Month/$post_month}"
                    formatted_path="${formatted_path//Day/$post_day}"
                    formatted_path="${formatted_path//slug/$slug}"
                    local display_date_format="$DATE_FORMAT"
                    if [ "${SHOW_TIMEZONE:-false}" = false ]; then
                        display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
                    fi
                    local formatted_date=$(format_date "$date" "$display_date_format")
                    local post_link="/$formatted_path/"
                    cat >> "$output_file" << EOF
            <article>
                <h3><a href="$(fix_url "$post_link")">$title</a></h3>
                <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $formatted_date${author_name:+" ${MSG_BY:-"by"} ${author_name:-$AUTHOR_NAME}"}</div>
EOF
                    if [ -n "$image" ]; then
                        local image_url="$image"
                        if [[ "$image" == /* ]]; then image_url="${SITE_URL}${image}"; fi
                        cat >> "$output_file" << EOF
                <div class="featured-image index-image">
                    <a href="$(fix_url "$post_link")">
                        <img src="$image_url" alt="${image_caption:-$title}" title="${image_caption:-$title}" />
                    </a>
                </div>
EOF
                    fi
                    # Show either full content or just description based on config
                    if [ "${INDEX_SHOW_FULL_CONTENT:-false}" = "true" ]; then
                        # Show full post content
                        local post_content=""
                        local content_cache_file="${CACHE_DIR:-.bssg_cache}/content/$(basename "$file")"

                        # Try RAM preload first
                        if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$file"; then
                            local source_stream
                            source_stream=$(ram_mode_get_content "$file")
                            post_content=$(printf '%s\n' "$source_stream" | awk '
                                BEGIN { in_fm = 0; found_fm = 0; }
                                /^---$/ {
                                    if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
                                    if (in_fm) { in_fm = 0; next; }
                                }
                                { if (!in_fm) print; }
                            ')
                        # Try to get content from cache first
                        elif [ -f "$content_cache_file" ]; then
                            post_content=$(cat "$content_cache_file")
                        else
                            # Extract content from source file if cache doesn't exist
                            local in_frontmatter=false
                            local found_frontmatter=false
                            {
                                while IFS= read -r line; do
                                    if [[ "$line" == "---" ]]; then
                                        if ! $in_frontmatter && ! $found_frontmatter; then
                                            in_frontmatter=true
                                            found_frontmatter=true
                                            continue
                                        elif $in_frontmatter; then
                                            in_frontmatter=false
                                            continue
                                        fi
                                    fi
                                    if ! $in_frontmatter && $found_frontmatter; then
                                        post_content+="$line"$'\n'
                                    fi
                                done
                            } < "$file"

                            # If no frontmatter was found, use the whole file
                            if ! $found_frontmatter; then
                                post_content=$(cat "$file")
                            fi
                        fi

                        # Convert to HTML if it's a markdown file
                        local html_content=""
                        if [[ "$file" == *.md ]]; then
                            html_content=$(convert_markdown_to_html "$post_content")
                        elif [[ "$file" == *.html ]]; then
                            # For HTML files, content is already HTML
                            html_content=$(sed -n '/<body.*>/,/<\/body>/p' "$file" | sed '1d;$d')
                            # If body extraction failed, use content as-is
                            if [ -z "$html_content" ]; then
                                html_content="$post_content"
                            fi
                        else
                            html_content="$post_content"
                        fi

                        if [ -n "$html_content" ]; then
                            cat >> "$output_file" << EOF
                <div class="post-content">
                    $html_content
                </div>
EOF
                        fi
                    elif [ -n "$description" ]; then
                        # Show just the description/excerpt (default behavior)
                        cat >> "$output_file" << EOF
                <div class="summary">
                    $description
                </div>
EOF
                    fi
                    cat >> "$output_file" << EOF

            </article>
EOF
                done # End of while loop reading posts

                # Close the posts list div
                cat >> "$output_file" << EOF
</div> <!-- .posts-list -->
EOF

                # Pagination logic (Only needed if there were posts)
                if [ "$total_pages" -gt 1 ]; then
                    cat >> "$output_file" << EOF

<!-- Pagination -->
<div class="pagination">
EOF
                    if [ "$current_page" -gt 1 ]; then
                        local prev_page=$((current_page - 1))
                        local prev_url="/"
                        if [ $prev_page -ne 1 ]; then prev_url="/page/$prev_page/"; fi
                        cat >> "$output_file" << PAG_EOF
    <a href="$(fix_url "$prev_url")" class="prev">&laquo; ${MSG_NEWER_POSTS:-Newer}</a>
PAG_EOF
                    fi
                    cat >> "$output_file" << PAG_EOF
    <span class="page-info">$(printf "${MSG_PAGE_INFO_TEMPLATE:-Page %d of %d}" "$current_page" "$total_pages")</span>
PAG_EOF
                    if [ "$current_page" -lt "$total_pages" ]; then
                        local next_page=$((current_page + 1))
                        cat >> "$output_file" << PAG_EOF
    <a href="$(fix_url "/page/$next_page/")" class="next">${MSG_OLDER_POSTS:-Older} &raquo;</a>
PAG_EOF
                    fi
                    cat >> "$output_file" << EOF
</div>
EOF
                fi # End pagination check
            else
                 # No index.md and no posts - display a message or leave blank?
                 # Currently implies a blank content area between header/footer.
                 echo "No posts found and no custom index.md; homepage will be mostly empty."
            fi # End of if total_posts_orig > 0

            # Add footer (always needed in the 'else' case)
            cat >> "$output_file" << EOF
$page_footer
EOF
        fi # End of if [ -f "${PAGES_DIR}/index.md" ] ... else ...

        # This message will now only be reached if index.md was NOT used.
        echo -e "Generated index page ${GREEN}$current_page${NC} of ${GREEN}$total_pages${NC}"
    }
    
    # Use GNU parallel if available and beneficial
    if [ "${HAS_PARALLEL:-false}" = true ] && [ "$total_pages" -gt 2 ] ; then
        echo -e "${GREEN}Using GNU parallel to process index pages${NC}"
        local cores
        cores=$(get_parallel_jobs)

        # Use all detected cores
        local jobs=$cores

        # Export required functions and variables
        export OUTPUT_DIR URL_SLUG_FORMAT POSTS_PER_PAGE CACHE_DIR
        export SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME DATE_FORMAT SITE_URL
        export FORCE_REBUILD HEADER_TEMPLATE FOOTER_TEMPLATE SHOW_TIMEZONE
        export INDEX_SHOW_FULL_CONTENT
        export MSG_LATEST_POSTS MSG_HOME MSG_PAGINATION_TITLE MSG_PUBLISHED_ON MSG_BY
        export MSG_NEWER_POSTS MSG_OLDER_POSTS MSG_PAGE_INFO_TEMPLATE
        # Note: total_posts_orig is NOT exported, passed as argument now
        export -f process_index_page file_needs_rebuild get_file_mtime format_date generate_slug fix_url convert_markdown_to_html
        
        # Ensure templates are exported
        if [ -z "$HEADER_TEMPLATE" ] || [ -z "$FOOTER_TEMPLATE" ]; then
             echo -e "${RED}Error: Header or Footer template not loaded/exported correctly.${NC}"
             return 1
        fi
        
        # Process pages in parallel, passing total_posts_orig as the 4th argument
        seq 1 $total_pages | parallel --jobs $jobs --will-cite process_index_page {} $total_pages "$file_index" $total_posts_orig || { echo -e "${RED}Parallel index page generation failed.${NC}"; exit 1; }
    else
        # Sequential implementation
        echo -e "${YELLOW}Using sequential processing${NC}"
        local current_page=1
        while [ "$current_page" -le "$total_pages" ]; do
            process_index_page $current_page $total_pages "$file_index" $total_posts_orig
            current_page=$((current_page + 1))
        done
    fi
    
    echo -e "${GREEN}Index pages processed!${NC}"
}

# Make the function available for sourcing
export -f generate_index 
