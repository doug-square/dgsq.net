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

# ==============================================================================
# Helper Functions for Archive Generation
# ==============================================================================

# Check if the main archive index page needs rebuilding
_check_archive_index_rebuild_needed() {
    local archive_index_file="$CACHE_DIR/archive_index.txt"
    local archives_index_page="$OUTPUT_DIR/archives/index.html"
    local rebuild_reason=""

    # 1. Force rebuild flag
    if [ "$FORCE_REBUILD" = true ]; then
        rebuild_reason="Force rebuild flag set."
    # 2. Config changed
    elif [ "$BSSG_CONFIG_CHANGED_STATUS" -eq 0 ]; then
        rebuild_reason="Global config changed."
    # 3. Output index page missing
    elif [ ! -f "$archives_index_page" ]; then
        rebuild_reason="Archive index page '$archives_index_page' missing."
    # 4. Templates changed (header/footer are global dependencies)
    elif [ -f "$archives_index_page" ]; then
        local template_dir="${TEMPLATES_DIR:-templates}"
        if [ -d "$template_dir/${THEME:-default}" ]; then template_dir="$template_dir/${THEME:-default}"; fi
        local header_template="$template_dir/header.html"
        local footer_template="$template_dir/footer.html"
        local output_time=$(get_file_mtime "$archives_index_page")
        local header_time=$(get_file_mtime "$header_template")
        local footer_time=$(get_file_mtime "$footer_template")
        if (( header_time > output_time )) || (( footer_time > output_time )); then
             rebuild_reason="Header or footer template changed."
        fi
    # 5. Explicit rebuild needed based on month count comparison
    elif [ "${ARCHIVE_INDEX_NEEDS_REBUILD:-false}" = true ]; then
        rebuild_reason="Archive month counts changed (detected by identify_affected_archive_months)."
    fi

    if [ -n "$rebuild_reason" ]; then
        echo -e "${YELLOW}Main archive index rebuild needed: $rebuild_reason${NC}" >&2 # Debug
        return 0 # Needs rebuild
    else
        return 1 # No rebuild needed
    fi
}


# Generate the main archives index page (archives/index.html)
_generate_main_archive_index() {
    local archive_index_file="$CACHE_DIR/archive_index.txt"
    local archives_index_page="$OUTPUT_DIR/archives/index.html"

    echo "Generating main archive index page: $archives_index_page" >&2 # Debug

    # Create archives directory if it doesn't exist
    mkdir -p "$(dirname "$archives_index_page")"

    # Get unique years sorted descending
    local unique_years=""
    if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
        unique_years=$(cut -d'|' -f1 "$archive_index_file" | sort -nr | uniq)
    fi

    # Generate header
    local header_content="$HEADER_TEMPLATE"
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"${MSG_ARCHIVES:-"Archives"}"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_type\}\}/"website"}
    header_content=${header_content//\{\{page_url\}\}/"archives/"} # Relative URL for header placeholder
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    header_content=${header_content//\{\{og_image\}\}/""}
    header_content=${header_content//\{\{twitter_image\}\}/""}
    # Add schema
    local schema_json_ld='<script type="application/ld+json">{"@context": "https://schema.org","@type": "CollectionPage","name": "Archives","description": "'"$SITE_DESCRIPTION"'","url": "'"$SITE_URL"'/archives/","isPartOf": {"@type": "WebSite","name": "'"$SITE_TITLE"'","url": "'"$SITE_URL"'"}}</script>'
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}


    # Generate footer
    local footer_content="$FOOTER_TEMPLATE"
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

    # Create the archives index page content
    {
        echo "$header_content"
        echo "<h1>${MSG_ARCHIVES:-"Archives"}</h1>"
        echo "<div class=\"archives-list year-list\">"

        # Loop through years (Existing logic for Year/Month links)
        echo "$unique_years" | while IFS= read -r year; do
            [ -z "$year" ] && continue

            local year_url
            year_url=$(fix_url "/archives/$year/")

            echo "    <h2><a href=\"$year_url\">$year</a></h2>"
            # Changed class to support potential block layout for month + posts
            echo "    <ul class=\"month-list-detailed\">" 

            # Get unique months for this year, sorted descending by month number
            local months_in_year=""
            if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
                months_in_year=$(grep "^$year|" "$archive_index_file" 2>/dev/null | cut -d'|' -f2,3 | sort -t'|' -k1,1nr | uniq)
            fi

            # Add month links and potentially post lists
            echo "$months_in_year" | while IFS= read -r month_line; do
                local month month_name
                # IMPORTANT: month is the numeric month (1-12) from the index
                IFS='|' read -r month month_name <<< "$month_line"
                [ -z "$month" ] && continue

                local month_post_count=0
                if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
                     # Use the numeric month for grep
                     month_post_count=$(grep -c "^$year|$month|" "$archive_index_file" 2>/dev/null || echo 0)
                fi

                local month_idx_formatted=$(printf "%02d" "$((10#$month))")
                local month_var_name="MSG_MONTH_$month_idx_formatted"
                local current_month_name=${!month_var_name:-$month_name}
                local month_url
                month_url=$(fix_url "/archives/$year/$month_idx_formatted/")

                # Start the list item for the month
                echo "        <li>"
                # Print the month link itself
                echo "            <a href=\"$month_url\">$current_month_name ($month_post_count)</a>"

                # --- START: Add nested post list if configured ---
                if [ "${ARCHIVES_LIST_ALL_POSTS:-false}" = true ] && [ "$month_post_count" -gt 0 ]; then
                    echo "            <ul class=\"post-list-condensed-inline\">" # Nested list for posts

                    local post_year post_month post_day url_path post_url

                    # Grep posts for this specific year and numeric month, sort chronologically
                    grep "^$year|$month|" "$archive_index_file" 2>/dev/null | sort -t'|' -k5,5 | while IFS='|' read -r _ _ _ title date _ filename slug _; do
                        # Construct post URL (logic adapted from process_single_month)
                        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                            post_year="${BASH_REMATCH[1]}"
                            post_month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                            post_day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
                        else
                            post_year=$(date +%Y); post_month=$(date +%m); post_day=$(date +%d) # Fallback
                        fi
                        
                        url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
                        url_path="${url_path//Year/$post_year}"
                        url_path="${url_path//Month/$post_month}"
                        url_path="${url_path//Day/$post_day}"
                        url_path="${url_path//slug/$slug}"
                        
                        post_url="/$(echo "$url_path" | sed 's|^/||; s|/*$|/|')"
                        post_url=$(fix_url "$post_url") # Use fix_url for BASE_URL prefixing if needed

                        # Extract just the date part (YYYY-MM-DD)
                        local display_date=$(echo "$date" | cut -d' ' -f1)

                        echo "                <li><a href=\"$post_url\">[$display_date] $title</a></li>"
                    done

                    echo "            </ul>" # Close nested post list
                fi
                # --- END: Add nested post list ---

                # Close the list item for the month
                echo "        </li>"
            done

            echo "    </ul>" # End of month-list-detailed
        done

        echo "</div>" # End of year-list div

        echo "$footer_content"

    } > "$archives_index_page"

    echo -e "Generated ${GREEN}$archives_index_page${NC}"
}

# Generate the index page for a specific year (archives/YYYY/index.html)
# This is called only if at least one month within the year needs updating.
_generate_year_index() {
    local year="$1"
    local archive_index_file="$CACHE_DIR/archive_index.txt"
    local year_index_page="$OUTPUT_DIR/archives/$year/index.html"

    echo "Generating year index page: $year_index_page" >&2 # Debug

    mkdir -p "$(dirname "$year_index_page")"

    # Generate header
    local header_content="$HEADER_TEMPLATE"
    local year_page_title="${MSG_ARCHIVES_FOR:-"Archives for"} $year"
    local year_archive_rel_url="/archives/$year/"
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"$year_page_title"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_type\}\}/"website"}
    header_content=${header_content//\{\{page_url\}\}/"$year_archive_rel_url"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    header_content=${header_content//\{\{og_image\}\}/""}
    header_content=${header_content//\{\{twitter_image\}\}/""}
    # Add schema
    local schema_json_ld='<script type="application/ld+json">{"@context": "https://schema.org","@type": "CollectionPage","name": "'"$year_page_title"'","description": "Archive of posts from '"$year"'","url": "'"$SITE_URL$year_archive_rel_url"'","isPartOf": {"@type": "WebSite","name": "'"$SITE_TITLE"'","url": "'"$SITE_URL"'"}}</script>'
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

    # Generate footer
    local footer_content="$FOOTER_TEMPLATE"
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

    # Create the year index page content
    {
        echo "$header_content"
        echo "<h1>$year_page_title</h1>"
        echo "<ul class=\"month-list\">"

        # Get unique months for this year, sorted descending by month number
        local months_in_year=""
        if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
            months_in_year=$(grep "^$year|" "$archive_index_file" 2>/dev/null | cut -d'|' -f2,3 | sort -t'|' -k1,1nr | uniq)
        fi

        # Add month links
        echo "$months_in_year" | while IFS= read -r month_line; do
            local month month_name
            IFS='|' read -r month month_name <<< "$month_line"
            [ -z "$month" ] && continue

            local month_post_count=0
            if [ -f "$archive_index_file" ] && [ -s "$archive_index_file" ]; then
                month_post_count=$(grep -c "^$year|$month|" "$archive_index_file" 2>/dev/null || echo 0)
            fi

            local month_idx_formatted=$(printf "%02d" "$((10#$month))")
            local month_var_name="MSG_MONTH_$month_idx_formatted"
            local current_month_name=${!month_var_name:-$month_name}
            local month_url
            month_url=$(fix_url "/archives/$year/$month_idx_formatted/")

            echo "<li><a href=\"$month_url\">$current_month_name ($month_post_count)</a></li>"
        done

        echo "</ul>"
        echo "$footer_content"

    } > "$year_index_page"

    echo -e "Generated ${GREEN}$year_index_page${NC}"
}


# Generate the index page for a specific month (archives/YYYY/MM/index.html)
process_single_month() {
    local year="$1"
    local month_num="$2" # Expecting MM format (01-12)
    local archive_index_file="$CACHE_DIR/archive_index.txt"
    local month_index_page="$OUTPUT_DIR/archives/$year/$month_num/index.html"

    echo "Processing month archive: $year-$month_num -> $month_index_page" >&2 # Debug

    mkdir -p "$(dirname "$month_index_page")"

    # Get month name (from locale or fallback)
    local month_name_var="MSG_MONTH_${month_num}"
    local month_name=${!month_name_var}
    if [[ -z "$month_name" ]]; then # Fallback using date command
        local input_date_for_month_name="${year}-${month_num}-01"
        if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *bsd* ]]; then
            month_name=$(date -j -f "%Y-%m-%d" "$input_date_for_month_name" "+%B" 2>/dev/null)
        else
            month_name=$(date -d "$input_date_for_month_name" "+%B" 2>/dev/null)
        fi
        [[ -z "$month_name" ]] && month_name="Month $month_num" # Final fallback
    fi

    # Generate header
    local header_content="$HEADER_TEMPLATE"
    local month_page_title="${MSG_ARCHIVES_FOR:-\"Archives for\"} $month_name $year"
    local month_archive_rel_url="/archives/$year/$month_num/"
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"$month_page_title"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_type\}\}/"website"}
    header_content=${header_content//\{\{page_url\}\}/"$month_archive_rel_url"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    header_content=${header_content//\{\{og_image\}\}/""}
    header_content=${header_content//\{\{twitter_image\}\}/""}
    # Add schema
    local schema_json_ld='<script type="application/ld+json">{"@context": "https://schema.org","@type": "CollectionPage","name": "'"$month_page_title"'","description": "Archive of posts from '"$month_name $year"'","url": "'"$SITE_URL$month_archive_rel_url"'","isPartOf": {"@type": "WebSite","name": "'"$SITE_TITLE"'","url": "'"$SITE_URL"'"}}</script>'
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

    # Generate footer
    local footer_content="$FOOTER_TEMPLATE"
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

    # Create the month index page content
    {
        echo "$header_content"
        echo "<h1>$month_page_title</h1>"
        echo "<div class=\"posts-list\">"

        # Grep for posts from this specific month and year
        grep "^$year|$month_num|" "$archive_index_file" 2>/dev/null | while IFS='|' read -r _ _ _ title date lastmod filename slug image image_caption description; do
            # --- Start: Card Generation Logic (copied from generate_tags.sh) ---
            local post_url post_year post_month post_day url_path

            # Replicate URL generation logic from generate_posts.sh
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                post_year="${BASH_REMATCH[1]}"
                post_month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                post_day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                # Fallback if date parsing fails (should be rare with indexing)
                post_year=$(date +%Y); post_month=$(date +%m); post_day=$(date +%d)
            fi

            url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
            url_path="${url_path//Year/$post_year}"
            url_path="${url_path//Month/$post_month}"
            url_path="${url_path//Day/$post_day}"
            url_path="${url_path//slug/$slug}"

            # Ensure relative URL starts with / and ends with /
            post_url="/$(echo "$url_path" | sed 's|^/||; s|/*$|/|')"
            # Prepend SITE_URL for the final href
            post_url="${SITE_URL}${post_url}"

            # Format date
            local display_date_format="$DATE_FORMAT"
            if [ "${SHOW_TIMEZONE:-false}" = false ]; then
                display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
            fi
            local formatted_date=$(format_date "$date" "$display_date_format")

            # Use cat heredoc for multi-line article structure
            cat << EOF
    <article>
        <h3><a href="${post_url}">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-\"Published on\"} $formatted_date</div>
EOF

            if [ -n "$image" ]; then
                local image_url=$(fix_url "$image")
                local alt_text="${image_caption:-$title}"
                local figcaption_content="${image_caption:-$title}"
                # Use cat heredoc for figure structure
                cat << EOF
        <figure class="featured-image tag-image">
            <a href="${post_url}">
                <img src="$image_url" alt="$alt_text" />
            </a>
            <figcaption>$figcaption_content</figcaption>
        </figure>
EOF
            fi

            if [ -n "$description" ]; then
                # Use cat heredoc for summary structure
                cat << EOF
        <div class="summary">
            $description
        </div>
EOF
            fi

            # Use cat heredoc for closing article tag
            cat << EOF
    </article>
EOF
            # --- End: Card Generation Logic ---
        done

        # Close the div instead of ul
        echo "</div>"
        echo "$footer_content"

    } > "$month_index_page"

    echo -e "Generated ${GREEN}$month_index_page${NC}"

}

# Wrapper function for parallel processing to handle argument parsing
_process_single_month_parallel_wrapper() {
    local line="$1"
    local year month_num
    # Parse the input line
    IFS='|' read -r year month_num <<< "$line"
    # Call the original function with parsed arguments
    process_single_month "$year" "$month_num"
}

# ==============================================================================
# Main Archive Generation Orchestrator
# ==============================================================================
generate_archive_pages() {
    echo -e "${YELLOW}Processing archive pages...${NC}"

    local archive_index_file="$CACHE_DIR/archive_index.txt"

    # Check if the archive index file exists (needed for any processing)
    if [ ! -f "$archive_index_file" ]; then
        echo -e "${YELLOW}Warning: Archive index file not found at '$archive_index_file'. Skipping archive generation.${NC}"
        return 0
    fi

    # --- Step 1: Handle Main Archive Index Page ---
    if _check_archive_index_rebuild_needed; then
        _generate_main_archive_index
    else
        echo -e "${GREEN}Main archive index page is up to date, skipping generation.${NC}"
    fi

    # --- Step 2: Handle Monthly and Yearly Pages based on Affected Months ---
    
    # Trim leading/trailing whitespace from AFFECTED_ARCHIVE_MONTHS just in case
    AFFECTED_ARCHIVE_MONTHS=$(echo "$AFFECTED_ARCHIVE_MONTHS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -z "$AFFECTED_ARCHIVE_MONTHS" ]; then
        echo -e "${GREEN}No affected archive months found. Skipping monthly/yearly page generation.${NC}"
        return 0
    fi

    echo "Affected months needing update: $AFFECTED_ARCHIVE_MONTHS" >&2 # Debug

    # --- Prepare for potential parallel processing ---
    local affected_years=()
    local affected_months_list=()
    local unique_years_map # Use associative array to track years needing update

    # Bash 4+ required for associative arrays
    if (( BASH_VERSINFO[0] < 4 )); then
       echo -e "${RED}Error: Bash 4+ required for optimized archive generation.${NC}" >&2
       # Fallback to non-parallel or exit? For now, just error out.
       return 1
    fi
    declare -A unique_years_map # Associative array requires Bash 4+

    for month_pair in $AFFECTED_ARCHIVE_MONTHS; do
        local year month_num
        IFS='|' read -r year month_num <<< "$month_pair"
        
        # Ensure month has leading zero for consistency
        month_num=$(printf "%02d" "$((10#$month_num))") 
        
        # Add to list for month processing
        affected_months_list+=("$year|$month_num")
        
        # Mark year as needing its index page updated
        unique_years_map["$year"]=1
    done

    # Extract unique years that need updating
    affected_years=("${!unique_years_map[@]}")
    
    if [ ${#affected_months_list[@]} -eq 0 ]; then
        echo -e "${GREEN}No valid affected months parsed. Nothing to do.${NC}"
        return 0
    fi
    
    echo "Processing ${#affected_months_list[@]} affected month(s) across ${#affected_years[@]} year(s)." >&2 # Debug

    # --- Generate Year Index Pages (Sequentially or Parallel?) ---
    # Generating year pages is usually fast. Let's do it sequentially first.
    echo "Generating/Updating affected year index pages..." >&2 # Debug
    for year in "${affected_years[@]}"; do
         _generate_year_index "$year"
    done
    echo "Affected year index pages updated." >&2 # Debug

    # --- Generate Monthly Pages (Parallel if available) ---
    echo "Generating/Updating affected monthly index pages..." >&2 # Debug
    if [ "$HAS_PARALLEL" = true ]; then
        # --- Parallel processing ---
        echo -e "${GREEN}Using GNU parallel to process monthly archive pages${NC}"

        # Determine number of cores/jobs
        local cores=1
        if command -v nproc > /dev/null 2>&1; then cores=$(nproc);
        elif command -v sysctl > /dev/null 2>&1; then cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1); fi
        local jobs=$cores # Use all detected cores
        if [ $jobs -gt ${#affected_months_list[@]} ]; then jobs=${#affected_months_list[@]}; fi # Don't use more jobs than items

        # Explicitly re-source utils.sh just in case environment is lost (shouldn't be needed if main.sh exports correctly, but safer)
        # shellcheck source=utils.sh disable=SC1091
        source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to re-source utils.sh for parallel export"; return 1; }

        # Export necessary variables and the processing function
        export CACHE_DIR OUTPUT_DIR SITE_TITLE SITE_DESCRIPTION SITE_URL AUTHOR_NAME HEADER_TEMPLATE FOOTER_TEMPLATE MSG_ARCHIVES_FOR MSG_MONTH_01 MSG_MONTH_02 MSG_MONTH_03 MSG_MONTH_04 MSG_MONTH_05 MSG_MONTH_06 MSG_MONTH_07 MSG_MONTH_08 MSG_MONTH_09 MSG_MONTH_10 MSG_MONTH_11 MSG_MONTH_12 URL_SLUG_FORMAT DATE_FORMAT TIMEZONE SHOW_TIMEZONE
        # Export needed functions (utils.sh sourced above, cache.sh sourced at top of main script)
        export -f process_single_month format_date fix_url get_file_mtime
        export -f _process_single_month_parallel_wrapper # Export the wrapper function

        # Call the wrapper function, passing the whole line {}
        printf "%s\n" "${affected_months_list[@]}" | \
            parallel --jobs "$jobs" --will-cite --no-notice _process_single_month_parallel_wrapper {} || { echo -e "${RED}Parallel monthly archive processing failed.${NC}"; return 1; }

        # Consider unexporting? Not strictly necessary as script exits soon.
    else
        # --- Sequential processing ---
        echo -e "${YELLOW}Using sequential processing for monthly archive pages${NC}"
        for month_pair in "${affected_months_list[@]}"; do
             local year month_num
             IFS='|' read -r year month_num <<< "$month_pair"
             process_single_month "$year" "$month_num"
        done
    fi

    echo "Affected monthly index pages updated." >&2 # Debug
    echo -e "${GREEN}Archive page processing complete.${NC}"
}

# Make the function available for sourcing
export -f generate_archive_pages 