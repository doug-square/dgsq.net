#!/usr/bin/env bash
#
# BSSG - Archive Page Generation
# Handles the creation of yearly and monthly archive pages and the main archive index.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_archives.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_archives.sh"; exit 1; }

# Generate archive pages for years and months
generate_archive_pages() {
    echo -e "${YELLOW}Processing archive pages...${NC}"
    
    # Only rebuild archives if archive cache index or templates changed
    local archive_index_file="$CACHE_DIR/archive_index.txt"
    local archives_index="$OUTPUT_DIR/archives/index.html"
    if [ -f "$archives_index" ] && ! file_needs_rebuild "$archive_index_file" "$archives_index"; then
        echo -e "${GREEN}Archive pages are up to date, skipping...${NC}"
        return
    fi
    
    # Check if the archive index file exists
    if [ ! -f "$archive_index_file" ]; then
        echo -e "${RED}Error: Archive index file not found at $archive_index_file${NC}"
        return 1
    fi

    # Create archives directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR/archives"

    # Get unique years sorted descending
    local unique_years=""
    if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
        unique_years=$(cut -d'|' -f1 "$archive_index_file" | sort -nr | uniq)
    fi

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
<div class="archives-list year-list">
EOF

    # Loop through years
    echo "$unique_years" | while read -r year; do
        # Skip empty lines just in case
        [ -z "$year" ] && continue
        
        # Pre-calculate year URL
        local year_url
        year_url=$(fix_url "/archives/$year/")

        cat >> "$archives_index" << EOF
    <h2><a href="$year_url">$year</a></h2>
    <ul class="month-list-inline">
EOF

        # Get unique months for this year, sorted descending by month number
        local months_in_year=""
        if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
            months_in_year=$(grep "^$year|" "$archive_index_file" 2>/dev/null | cut -d'|' -f2,3 | sort -t'|' -k1,1nr | uniq)
        fi

        # Add month links
        echo "$months_in_year" | while read -r month_line; do
            local month month_name
            IFS='|' read -r month month_name <<< "$month_line"
            
            if [ -z "$month" ]; then continue; fi
            
            local month_post_count=0
            if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
                month_post_count=$(grep -c "^$year|$month|" "$archive_index_file" 2>/dev/null || echo 0)
            fi
            
            # Use locale variable for month name
            local month_idx_formatted=$(awk -v m="$month" 'BEGIN { printf "%02d", m }')
            local month_var_name="MSG_MONTH_$month_idx_formatted"
            local current_month_name=${!month_var_name:-$month_name} 
            
            # Pre-calculate month URL
            local month_url
            month_url=$(fix_url "/archives/$year/$month_idx_formatted/")

            cat >> "$archives_index" << EOF
            <li><a href="$month_url">$current_month_name ($month_post_count)</a></li>
EOF
        done

        echo "</ul>" >> "$archives_index"
    done

    # Close the archives index page
    cat >> "$archives_index" << EOF
</div>
$footer_content
EOF
  echo -e "Generated ${GREEN}archives/index.html${NC}"

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
        
        # Skip if page is up-to-date (based on archive index file)
        if ! parallel_file_needs_rebuild "$archive_index_file" "$year_index"; then
          echo -e "Skipping unchanged year archive: ${YELLOW}$year${NC}"
          # We still need to process months within this year, even if year index is unchanged
        else
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
          
          # Set proper URL in og:url with trailing slash
          local year_archive_rel_url="/archives/$year/"
          header_content=${header_content//\{\{page_url\}\}/"$year_archive_rel_url"}
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
  "url": "$SITE_URL${year_archive_rel_url}",
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

        fi # End of check for year index rebuild

        # Get unique months for this year (needed regardless of whether year index was rebuilt)
        local unique_months=""
        if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
            unique_months=$(grep "^$year|" "$archive_index_file" 2>/dev/null | awk -F'|' '{print $2 "|" $3}' | sort -r | uniq)
        fi
        
        # Add months to the year page and process each month
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
                local month_idx_formatted=$(awk -v m="$month" 'BEGIN { printf "%02d", m }')
                local month_var_name="MSG_MONTH_$month_idx_formatted"
                local current_month_name=${!month_var_name:-$month_name} 
                
                # Add month link to year index only if it was rebuilt
                if [ -f "$year_index" ]; then # Check if file exists (means it was created/rebuilt)
                   # Pre-calculate month URL
                   local month_url
                   month_url=$(fix_url "/archives/$year/$month_idx_formatted/")
                   cat >> "$year_index" << EOF
    <h2><a href="$month_url">$current_month_name <span class="post-count">($month_post_count ${MSG_POSTS:-\"posts\"})</span></a></h2>
EOF
                fi

                # Process this month, passing the formatted month index and translated name
                process_month "$year" "$month_idx_formatted" "$current_month_name"
            fi
        done
        
        # Close year index file only if it was rebuilt
        if [ -f "$year_index" ]; then
          cat >> "$year_index" << EOF
</div>
$footer_content
EOF
          echo -e "Generated archive page for year: ${GREEN}$year${NC}"
        fi
    }
    
    # Define function to process a single month
    process_month() {
        local year="$1"
        local month="$2" # Formatted month index (e.g., 09)
        local month_name="$3" # Potentially translated name
        local archive_index_file="$CACHE_DIR/archive_index.txt"
        
        # Create month page path (directory + index.html)
        local month_dir="$OUTPUT_DIR/archives/$year/$month"
        local month_file="$month_dir/index.html"
                
        # Skip if page is up-to-date
        if ! parallel_file_needs_rebuild "$archive_index_file" "$month_file"; then
          echo -e "Skipping unchanged month archive: ${YELLOW}$month_name $year${NC}"
          return 0
        fi

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
        
        # Set proper URL in og:url with trailing slash
        local month_archive_rel_url="/archives/$year/$month/"
        month_header_content=${month_header_content//\{\{page_url\}\}/"$month_archive_rel_url"}
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
  "url": "$SITE_URL${month_archive_rel_url}",
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

        # Pre-calculate navigation URLs
        local back_to_year_url
        back_to_year_url=$(fix_url "/archives/$year/")
        local archives_index_url
        archives_index_url=$(fix_url "/archives/")

        # Create the month index page
        mkdir -p "$month_dir" # Ensure directory exists
        cat > "$month_file" << EOF
$month_header_content
<h1>${MSG_ARCHIVES_FOR:-\"Archives for\"} $month_name $year</h1>

<div class="archives-nav">
    <a href="$back_to_year_url">${MSG_BACK_TO:-\"Back to\"} $year</a> | 
    <a href="$archives_index_url">${MSG_ARCHIVES:-\"Archives\"} Index</a>
</div>

<div class="post-list archive-list">
EOF

        # Add posts for this month
        local posts_for_month=""
        if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
            # Capture the filtered and sorted posts
            # Use $month (e.g., 04) directly in grep pattern to match index format
            posts_for_month=$(grep "^$year|$month|" "$archive_index_file" 2>/dev/null | sort -t'|' -k5 -r || true)
        fi

        # Check if any posts were found
        if [ -n "$posts_for_month" ]; then
            # Loop through the captured posts
            echo "$posts_for_month" | while IFS= read -r post_line; do
                if [ -z "$post_line" ]; then
                    continue
                fi
                
                local _ _ _ title date lastmod filename slug image image_caption description
                IFS='|' read -r _ _ _ title date lastmod filename slug image image_caption description <<< "$post_line"
                
                # Create slug-based URL path according to URL_SLUG_FORMAT
                local post_year post_month post_day
                if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                    post_year="${BASH_REMATCH[1]}"
                    post_month="${BASH_REMATCH[2]}"
                    post_day="${BASH_REMATCH[3]}"
                    post_month=$(awk -v m="$post_month" 'BEGIN { printf "%02d", m }')
                    post_day=$(awk -v d="$post_day" 'BEGIN { printf "%02d", d }')
                else
                    post_year=$(date +%Y)
                    post_month=$(date +%m)
                    post_day=$(date +%d)
                fi
                
                local formatted_path="${URL_SLUG_FORMAT//Year/$post_year}"
                formatted_path="${formatted_path//Month/$post_month}"
                formatted_path="${formatted_path//Day/$post_day}"
                formatted_path="${formatted_path//slug/$slug}"

                # Ensure link has trailing slash
                local post_link="/${formatted_path}/"

                # Format date based on SHOW_TIMEZONE
                local display_date_format="$DATE_FORMAT"
                if [ "${SHOW_TIMEZONE:-false}" = false ]; then
                    # Remove timezone format specifiers (%z or %Z) if they exist
                    display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
                fi
                local formatted_date=$(format_date "$date" "$display_date_format")

                cat >> "$month_file" << EOF
    <article>
        <h3><a href="${SITE_URL}${post_link}">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $formatted_date${AUTHOR_NAME:+" ${MSG_BY:-"by"} $AUTHOR_NAME"}</div>
EOF

                # Add featured image if specified
                if [ -n "$image" ]; then
                    # Process image URL
                    local image_url
                    image_url=$(fix_url "$image")

                    # Use title as fallback for alt text if caption is missing
                    local alt_text="${image_caption:-$title}"
                    local figcaption_content="${image_caption:-$title}"

                    cat >> "$month_file" << EOF
        <figure class="featured-image archive-image">
            <a href="${SITE_URL}${post_link}">
                <img src="$image_url" alt="$alt_text" />
            </a>
            <figcaption>$figcaption_content</figcaption>
        </figure>
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
            <a href="${SITE_URL}${post_link}">${MSG_READ_MORE:-"Read more"} →</a>
        </div>
    </article>
EOF
            done # End of while loop for posts_for_month
        else
            # Optional: Add a message if no posts were found for this month
            cat >> "$month_file" << EOF
    <p>${MSG_NO_POSTS_FOUND:-"No posts found for this month."}</p>
EOF
        fi # End of check if posts_for_month is not empty

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
            cores=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        fi

        # Export functions needed by parallel processes
        export -f process_year process_month parallel_file_needs_rebuild
        # Export required utility functions
        export -f get_file_mtime format_date fix_url
        # Export necessary variables (assumed to be globally exported already, but good practice)
        export OUTPUT_DIR CACHE_DIR SITE_URL SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME FORCE_REBUILD TEMPLATES_DIR HEADER_TEMPLATE FOOTER_TEMPLATE URL_SLUG_FORMAT DATE_FORMAT SHOW_TIMEZONE
        export MSG_ARCHIVES MSG_POSTS MSG_ARCHIVES_FOR MSG_BACK_TO MSG_PUBLISHED_ON MSG_BY MSG_READ_MORE MSG_MONTH_01 MSG_MONTH_02 MSG_MONTH_03 MSG_MONTH_04 MSG_MONTH_05 MSG_MONTH_06 MSG_MONTH_07 MSG_MONTH_08 MSG_MONTH_09 MSG_MONTH_10 MSG_MONTH_11 MSG_MONTH_12

        # Process years in parallel
        echo "$unique_years" | parallel --jobs "$cores" process_year {} 
    else
        # Sequential processing
        echo -e "${YELLOW}Using sequential processing${NC}"
        for year in $unique_years; do
            process_year "$year"
        done
    fi

    echo -e "${GREEN}Archive pages processed!${NC}"
}

# Make the function available for sourcing
export -f generate_archive_pages 