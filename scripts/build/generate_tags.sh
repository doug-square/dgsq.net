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
    local modified_tags_list_file="${CACHE_DIR:-.bssg_cache}/modified_tags.list"

    # Check if the tags index file exists (needed for listing tags)
    if [ ! -f "$tags_index_file" ]; then
        echo -e "${YELLOW}Tags index file not found at $tags_index_file. Skipping tag page generation.${NC}"
        # If the index doesn't exist, no tags were found in posts.
        # Ensure the main output directory exists but is empty.
        mkdir -p "$(dirname "$main_tags_index_output")"
        # Optionally create an empty index page? Or let it be absent? Let's ensure dir exists.
        echo -e "${GREEN}Tag pages processed! (No tags found)${NC}"
        echo -e "${GREEN}Generated tag list pages. (No tags found)${NC}"
        return 0
    fi

    # --- Calculate Latest Common Dependency Time --- START ---
    # Get mtimes of config hash, templates, and locale file
    # IMPORTANT: Assumes get_file_mtime, TEMPLATES_DIR, THEME, LOCALE_DIR, SITE_LANG, CONFIG_HASH_FILE are available
    local latest_common_dep_time=0
    local config_hash_time=$(get_file_mtime "$CONFIG_HASH_FILE")
    latest_common_dep_time=$(( config_hash_time > latest_common_dep_time ? config_hash_time : latest_common_dep_time ))

    local template_dir="${TEMPLATES_DIR:-templates}"
    if [ -d "$template_dir/${THEME:-default}" ]; then
        template_dir="$template_dir/${THEME:-default}"
    fi
    local header_template="$template_dir/header.html"
    local footer_template="$template_dir/footer.html"
    local header_time=$(get_file_mtime "$header_template")
    local footer_time=$(get_file_mtime "$footer_template")
    latest_common_dep_time=$(( header_time > latest_common_dep_time ? header_time : latest_common_dep_time ))
    latest_common_dep_time=$(( footer_time > latest_common_dep_time ? footer_time : latest_common_dep_time ))

    local active_locale_file=""
    if [ -f "${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh" ]; then
        active_locale_file="${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh"
    elif [ -f "${LOCALE_DIR:-locales}/en.sh" ]; then
        active_locale_file="${LOCALE_DIR:-locales}/en.sh"
    fi
    local locale_time=$(get_file_mtime "$active_locale_file")
    latest_common_dep_time=$(( locale_time > latest_common_dep_time ? locale_time : latest_common_dep_time ))
    #echo "Latest common dependency time: $latest_common_dep_time" >&2 # Debug
    # --- Calculate Latest Common Dependency Time --- END ---


    # --- Simplified Global Check --- START ---
    # Decide if we need to proceed with any tag generation steps at all.
    local proceed_with_generation=false
    local force_rebuild_status="${FORCE_REBUILD:-false}"

    if [ "$force_rebuild_status" = true ]; then
        proceed_with_generation=true
        echo "Force rebuild enabled, proceeding with tag generation." >&2 # Debug
    elif [ "$latest_common_dep_time" -gt 0 ] && { [ ! -f "$main_tags_index_output" ] || (( $(get_file_mtime "$main_tags_index_output") < latest_common_dep_time )); }; then
        # Common dependencies are newer than the main output (or main output missing)
        proceed_with_generation=true
        echo "Common dependencies changed, proceeding with tag generation." >&2 # Debug
    elif [ -s "$modified_tags_list_file" ]; then
        # Modified tags list exists and is not empty
        proceed_with_generation=true
        echo "Modified tags detected, proceeding with tag generation." >&2 # Debug
    elif [ ! -f "$main_tags_index_output" ]; then
        # Fallback: if main output is missing, we should generate it
         proceed_with_generation=true
         echo "Main tags index missing, proceeding with tag generation." >&2 # Debug
    fi

    if [ "$proceed_with_generation" = false ]; then
        echo -e "${GREEN}Tags index, tag pages${NC}${ENABLE_TAG_RSS:+, and tag RSS feeds} appear up to date based on common dependencies and modified posts, skipping.${NC}"
        echo -e "${GREEN}Tag pages processed!${NC}" # Keep consistent final message
        echo -e "${GREEN}Generated tag list pages.${NC}" # Keep consistent final message
        return 0
    fi
    # --- Simplified Global Check --- END ---


    # --- Proceed with Generation ---

    # Get unique tags (Tag|URL pairs)
    local unique_tags_lines=$(awk -F'|' '{print $1 "|" $2}' "$tags_index_file" | sort | uniq)
    local tag_count=$(echo "$unique_tags_lines" | grep -v '^$' | wc -l)
    echo -e "Checking ${GREEN}$tag_count${NC} tag pages${NC}${ENABLE_TAG_RSS:+/feeds} for changes (based on common deps & modified tags)" # Updated message

    # --- Pre-group posts by tag slug --- START ---
    local tag_data_dir="$CACHE_DIR/tag_data"
    rm -rf "$tag_data_dir" # Clean previous data
    mkdir -p "$tag_data_dir"
    echo -e "Pre-grouping posts by tag into ${BLUE}$tag_data_dir${NC}..."
    if awk -F'|' -v tag_dir="$tag_data_dir" '
        NF >= 2 { # Ensure at least tag and slug fields exist
            tag_slug = $2;
            if (tag_slug != "") {
                # Sanitize slug just in case for filename safety? (basic: remove /)
                gsub(/\//, "_", tag_slug);
                output_file = tag_dir "/" tag_slug ".tmp";
                print $0 >> output_file; # Append the whole line
                close(output_file); # Close file handle to avoid too many open files
            } else {
                print "Warning: Skipping line with empty tag slug in tags_index: " $0 > "/dev/stderr";
            }
        }
    ' "$tags_index_file"; then
        echo -e "${GREEN}Pre-grouping complete.${NC}"
        # --- Start Debug: Show content of a specific tag data file (e.g., bssg) ---
        # if [ -f "$tag_data_dir/bssg.tmp" ]; then
        #     echo "DEBUG: Content of $tag_data_dir/bssg.tmp after grouping:" >&2
        #     cat "$tag_data_dir/bssg.tmp" >&2
        #     echo "--- End $tag_data_dir/bssg.tmp DEBUG ---" >&2
        # else
        #     echo "DEBUG: $tag_data_dir/bssg.tmp not found after grouping." >&2
        # fi
        # --- End Debug ---
    else
        echo -e "${RED}Error: Failed to pre-group tag data using awk.${NC}" >&2
        return 1
    fi
    # --- Pre-group posts by tag slug --- END ---

    # Define a modified file_needs_rebuild function for parallel use - Now simpler
    # This version only checks if the specific tag output file is older than the
    # LATEST COMMON dependency time calculated during the global check.
    parallel_file_needs_rebuild() {
        local output_file="$1"
        # Use the pre-calculated common dependency time
        local latest_dep_time="$2" # This should be latest_common_dep_time

        # Rebuild if output file doesn't exist
        if [ ! -f "$output_file" ]; then
            return 0 # Rebuild needed
        fi

        local output_time=$(get_file_mtime "$output_file")

        # Rebuild if output is older than the latest relevant *common* dependency
        if (( output_time < latest_dep_time )); then
            return 0 # Rebuild needed
        fi

        return 1 # No rebuild needed
    }

    # Define a function to process a single tag
    process_tag() {
        local tag_line="$1"
        local tag_data_dir="$2"
        local latest_common_dep_time_for_tag="$3"
        local modified_tags_file="$4" # Accept filename instead of hash

        # --- Start Change: Load modified tags from file ---
        declare -A modified_tags_hash
        if [ -f "$modified_tags_file" ]; then
            local mod_tag_local
            while IFS= read -r mod_tag_local || [[ -n "$mod_tag_local" ]]; do
                if [ -n "$mod_tag_local" ]; then # Ensure not empty line
                    modified_tags_hash["$mod_tag_local"]=1
                fi
            done < "$modified_tags_file"
            # echo "DEBUG (process_tag): Loaded ${#modified_tags_hash[@]} modified tags from $modified_tags_file" >&2
        fi
        # --- End Change ---

        local tag tag_url
        IFS='|' read -r tag tag_url <<< "$tag_line"

        if [ -n "$tag" ]; then
            local tag_page_html_file="$OUTPUT_DIR/tags/$tag_url/index.html"
            local tag_rss_file="$OUTPUT_DIR/tags/$tag_url/${RSS_FILENAME:-rss.xml}"
            local tag_page_rel_url="/tags/${tag_url}/"
            local tag_rss_rel_url="/tags/${tag_url}/${RSS_FILENAME:-rss.xml}"
            local rebuild_html=false
            local rebuild_rss=false

            # --- Start Change: Force rebuild flags if tag was modified ---
            local tag_was_modified=false
            if [ -n "${modified_tags_hash[$tag]}" ]; then
                tag_was_modified=true
                rebuild_html=true # Force rebuild if tag was modified
                if [ "${ENABLE_TAG_RSS:-false}" = true ]; then
                     rebuild_rss=true # Force rebuild if tag was modified
                fi
                echo "Tag '$tag' marked as modified, forcing HTML/RSS rebuild flags." >&2 # Debug
            fi
            # --- End Change ---

            # Check if HTML page needs rebuild based on COMMON deps time (only if not already forced)
            if [ "$rebuild_html" = false ] && parallel_file_needs_rebuild "$tag_page_html_file" "$latest_common_dep_time_for_tag"; then
                rebuild_html=true
            fi
            # Check if RSS feed needs rebuild (only if enabled) based on COMMON deps time (only if not already forced)
            if [ "$rebuild_rss" = false ] && [ "${ENABLE_TAG_RSS:-false}" = true ]; then
                if parallel_file_needs_rebuild "$tag_rss_file" "$latest_common_dep_time_for_tag"; then
                    rebuild_rss=true
                fi
            fi

            # Proceed with generation as this function is only called for tags needing processing
            # Ensure at least one flag is true before proceeding (should always be true if called)
            if [ "$rebuild_html" = false ] && [ "$rebuild_rss" = false ]; then
                 echo "${YELLOW}Warning:${NC} Skipping tag '$tag' inside process_tag despite being in process list. Flags rebuild_html/rss are false." >&2 # Debug
                 return 0
            fi

            echo -e "Processing tag: ${GREEN}$tag${NC} (HTML: $rebuild_html, RSS: $rebuild_rss)" # Updated message
            mkdir -p "$OUTPUT_DIR/tags/$tag_url/" # Create directory if it doesn't exist

            # Define the path to the pre-grouped data file for this tag
            local tag_specific_data_file="${tag_data_dir}/${tag_url}.tmp"

            # Check if the specific data file exists (it should, unless the pre-grouping failed)
            if [ ! -f "$tag_specific_data_file" ]; then
                 echo -e "${RED}Error: Pre-grouped data file not found for tag '$tag' at $tag_specific_data_file${NC}" >&2
                 # Decide whether to skip or error out - let's skip this tag
                 return 1 # Or return 0 to continue with other tags?
            fi

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

                # Add posts for this tag - use the pre-grouped data file
                # local temp_file=$(mktemp)
                # awk -F'|' -v tag="$tag" -v url="$tag_url" '$1 == tag && $2 == url' "$tags_index_file" > "$temp_file"

                # Read directly from the pre-grouped file
                if [ -s "$tag_specific_data_file" ]; then # Check if file not empty
                    while IFS= read -r post_line; do
                        if [ -z "$post_line" ]; then continue; fi
                        # echo "DEBUG (process_tag for '$tag'): Processing post_line: $post_line" >&2 # Removed

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

                        # --- Start Debug: Check variables before appending article ---
                        #echo "DEBUGAPPEND (tag='$tag', title='$title'): Appending article HTML with link='$post_link', date='$formatted_date'" >&2
                        # --- End Debug ---

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
            $description
        </div>
EOF
                        fi

                        cat >> "$tag_page_html_file" << EOF
    </article>
EOF
                    done < "$tag_specific_data_file"
                fi
                # rm "$temp_file"

                # Close the tag page
                cat >> "$tag_page_html_file" << EOF
</div>
<p><a href="${SITE_URL}/tags/">${MSG_ALL_TAGS:-"All Tags"}</a></p>
$footer_content
EOF

                echo -e "  Generated HTML page for: ${GREEN}$tag${NC}"
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
                # IMPORTANT: tags_index.txt has format: Tag|TagSlug|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|Image|ImageCaption|PostDescription|OriginalFilePath
                # We need to map this to the format expected by _generate_rss_feed:
                # file|filename|title|date|lastmod|tags|slug|image|image_caption|description
                # We lack the original 'file' path and 'tags' string here. We can approximate.

                local tag_post_data_tmp=$(mktemp)
                # Read from pre-grouped file, sort, limit, and map fields using awk
                sort -t'|' -k4,4r -k5,5r "$tag_specific_data_file" | \
                head -n "$rss_item_limit" | \
                awk -F'|' -v tag_val="$tag" 'BEGIN {OFS="|"} {
                    # Reconstruct needed fields. Use filename ($6) as placeholder for first field.
                    # file (placeholder) | filename | title | date | lastmod | tags | slug | image | image_caption | description
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
                    # echo "DEBUG: In process_tag for '$tag', RSS_FILENAME='${RSS_FILENAME:-rss.xml}', tag_rss_file='${tag_rss_file}'" >&2 # DEBUG
                    _generate_rss_feed "$tag_rss_file" "$feed_title" "$feed_desc" "$feed_link_rel" "$feed_atom_link_rel" "$tag_post_data"
                    echo -e "  Generated RSS feed for: ${GREEN}$tag${NC}"
                fi

            fi # End RSS generation

        fi # End check for non-empty tag
    } # End process_tag function

    # Process tags either in parallel or sequentially
    local tags_to_process_list=()
    local skipped_tag_count=0
    # local force_rebuild_status="${FORCE_REBUILD:-false}" # Defined above
    # local modified_tags_list_file="${CACHE_DIR:-.bssg_cache}/modified_tags.list" # Defined above

    # --- Start Change: Load modified tags into memory for faster checking ---
    local modified_tags_set=()
    if [ -f "$modified_tags_list_file" ]; then
        mapfile -t modified_tags_set < <(grep . "$modified_tags_list_file") # Read non-empty lines into array
    fi
    declare -A modified_tags_hash # Use associative array for efficient lookup
    local mod_tag
    for mod_tag in "${modified_tags_set[@]}"; do
        modified_tags_hash["$mod_tag"]=1
    done
    echo "Loaded ${#modified_tags_hash[@]} unique modified tags into hash." >&2 # Debug
    # --- End Change ---

    # Loop through unique tags and decide which ones need processing
    while IFS= read -r tag_line; do
        if [ -z "$tag_line" ]; then continue; fi
        local tag tag_url
        IFS='|' read -r tag tag_url <<< "$tag_line"
        local tag_page_html_file="$OUTPUT_DIR/tags/$tag_url/index.html"
        local tag_rss_file="$OUTPUT_DIR/tags/$tag_url/${RSS_FILENAME:-rss.xml}"
        local process_this_tag=false # Flag to decide if this tag needs processing

        # --- Refined Check: Check if tag needs processing ---
        # Reason 1: Force rebuild enabled
        if [ "$force_rebuild_status" = true ]; then
            process_this_tag=true
        # Reason 2: Output file(s) outdated compared to COMMON dependencies
        # Pass the calculated latest_common_dep_time here
        elif parallel_file_needs_rebuild "$tag_page_html_file" "$latest_common_dep_time"; then
            process_this_tag=true
            #echo "Tag '$tag' HTML outdated vs common deps, marking for processing." >&2 # Debug
        elif [ "${ENABLE_TAG_RSS:-false}" = true ] && parallel_file_needs_rebuild "$tag_rss_file" "$latest_common_dep_time"; then
            process_this_tag=true
            #echo "Tag '$tag' RSS outdated vs common deps, marking for processing." >&2 # Debug
        # Reason 3: Tag was associated with a modified post
        elif [ -n "${modified_tags_hash[$tag]}" ]; then # Use compatible check
            process_this_tag=true
            #echo "Tag '$tag' was modified, marking for processing." >&2 # Debug
        fi
        # --- End Refined Check ---

        if $process_this_tag; then
             tags_to_process_list+=("$tag_line")
        else
             # This skip message should now be more accurate
             echo -e "Skipping unchanged tag (outputs up-to-date vs common deps AND tag not modified): ${YELLOW}$tag${NC}"
             skipped_tag_count=$((skipped_tag_count + 1))
        fi
    done < <(echo "$unique_tags_lines")

    local tags_to_process_count=${#tags_to_process_list[@]}

    if [ $tags_to_process_count -gt 0 ]; then
        echo -e "Found ${GREEN}$tags_to_process_count${NC} tags needing processing (HTML${NC}${ENABLE_TAG_RSS:+ or RSS}) (Skipped: $skipped_tag_count).${NC}"
        # Use parallel 
        if [ "${HAS_PARALLEL:-false}" = true ] ; then
            echo -e "${GREEN}Using GNU parallel to process tag pages${NC}${ENABLE_TAG_RSS:+/feeds}"
            local cores=1
            if command -v nproc > /dev/null 2>&1; then cores=$(nproc);
            elif command -v sysctl > /dev/null 2>&1; then cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1); fi
            local jobs=$cores # Use all cores for tags by default if parallel

            # Export necessary functions and variables
            # ... [Existing exports] ...
            export -f process_tag parallel_file_needs_rebuild get_file_mtime fix_url format_date
            export OUTPUT_DIR CACHE_DIR SITE_URL SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME
            export HEADER_TEMPLATE FOOTER_TEMPLATE DATE_FORMAT TIMEZONE SHOW_TIMEZONE URL_SLUG_FORMAT
            export MSG_TAG_PAGE_TITLE MSG_PUBLISHED_ON MSG_BY MSG_READ_MORE MSG_ALL_TAGS

            if [ "${ENABLE_TAG_RSS:-false}" = true ]; then
                export -f _generate_rss_feed convert_markdown_to_html # From generate_feeds.sh & content.sh
                export MD5_CMD CACHE_DIR MARKDOWN_PROCESSOR MARKDOWN_PL_PATH RSS_INCLUDE_FULL_CONTENT # From deps/config
                export SITE_LANG RSS_ITEM_LIMIT MSG_POSTS_TAGGED_WITH # From config/locale
            fi
            # Pass the tag data directory and the COMMON dependency time
            export tag_data_dir latest_common_dep_time
            # --- Start Change: Pass modified tags filename to parallel --- 
            export modified_tags_list_file 

            # NetBSD Concurrency Fix: Removed as NetBSD is now excluded

            # Call parallel with the correct common dependency time and modified tags file
            printf "%s\n" "${tags_to_process_list[@]}" | parallel --jobs "$jobs" --will-cite process_tag {} "$tag_data_dir" "$latest_common_dep_time" "$modified_tags_list_file" || { echo -e "${RED}Parallel tag processing failed.${NC}"; exit 1; }
            # --- End Change --- 

        else
            # Handle sequential or NetBSD case
            if [ "${HAS_PARALLEL:-false}" = true ] && [ "$(uname -s)" = "NetBSD" ]; then
                 echo -e "${YELLOW}Detected NetBSD, using sequential processing for $tags_to_process_count tags${NC}"
            else
                 echo -e "${YELLOW}Using sequential processing for $tags_to_process_count tags${NC}"
            fi
            local tag_line
            for tag_line in "${tags_to_process_list[@]}"; do
                 # Pass the correct common dependency time and modified tags file
                process_tag "$tag_line" "$tag_data_dir" "$latest_common_dep_time" "$modified_tags_list_file"
            done
        fi
    else
         echo -e "${GREEN}All $tag_count individual tag pages${NC}${ENABLE_TAG_RSS:+ and RSS feeds} appear up to date.${NC}" # Updated message
    fi

    # --- Generate the main tags index page (tags/index.html) --- START ---
    echo -e "Generating tags/index.html"
    local main_tags_index_rebuild_needed=false
    local tags_index_prev_file="${CACHE_DIR:-.bssg_cache}/tags_index_prev.txt"
    local tags_changed=false # Flag to track if the set of tags changed

    # --- Start Change: Check if the set of unique tags has changed ---
    if [ ! -f "$tags_index_prev_file" ] && [ -f "$tags_index_file" ]; then
        tags_changed=true
        echo "Tags added (no previous index), main tags index rebuild needed." >&2 # Debug
    elif [ -f "$tags_index_prev_file" ] && [ ! -f "$tags_index_file" ]; then
        tags_changed=true
        echo "All tags removed (no current index), main tags index rebuild needed." >&2 # Debug
    elif [ -f "$tags_index_prev_file" ] && [ -f "$tags_index_file" ]; then
        local current_unique_tags=$(awk -F'|' '{print $1 "|" $2}' "$tags_index_file" | sort | uniq)
        local prev_unique_tags=$(awk -F'|' '{print $1 "|" $2}' "$tags_index_prev_file" | sort | uniq)
        if [ "$current_unique_tags" != "$prev_unique_tags" ]; then
            tags_changed=true
            echo "Set of unique tags changed, main tags index rebuild needed." >&2 # Debug
        fi
    fi
    # --- End Change ---

    # Decide if main tags index needs rebuild
    if [ "$force_rebuild_status" = true ]; then
        main_tags_index_rebuild_needed=true
        echo -e "${YELLOW}Force rebuild enabled for tags/index.html${NC}"
    elif $tags_changed; then # Rebuild if the set of tags changed
        main_tags_index_rebuild_needed=true
    elif [ "$tags_to_process_count" -gt 0 ]; then
        main_tags_index_rebuild_needed=true
        echo "Individual tag pages were processed, rebuilding main tags index for count updates." >&2 # Debug
    elif [ ! -f "$main_tags_index_output" ]; then # Rebuild if output missing
        main_tags_index_rebuild_needed=true
    # Rebuild if output is older than COMMON dependencies
    elif (( $(get_file_mtime "$main_tags_index_output") < latest_common_dep_time )); then
         main_tags_index_rebuild_needed=true
         echo "Main tags index outdated vs common deps, rebuilding." >&2 # Debug
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
                # Count lines in the pre-grouped data file for this tag
                local tag_specific_data_file="${tag_data_dir}/${tag_url}.tmp"
                if [ -f "$tag_specific_data_file" ]; then
                   post_count=$(wc -l < "$tag_specific_data_file" | tr -d ' ')
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
        echo -e "Skipping unchanged tags index ${YELLOW}(Set of tags unchanged AND output up-to-date vs common deps)${NC}" # Updated message
    fi
    # --- Generate the main tags index page --- END ---

    echo -e "${GREEN}Tag pages processed!${NC}"
}

# Export the main function for the build script
export -f generate_tag_pages 
