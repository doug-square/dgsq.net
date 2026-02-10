#!/usr/bin/env bash
#
# BSSG - Author Page Generation
# Handles the creation of individual author pages and the main author index.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_authors.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_authors.sh"; exit 1; }
# Source the feed generator script for the reusable RSS function
# shellcheck source=generate_feeds.sh disable=SC1091
source "$(dirname "$0")/generate_feeds.sh" || { echo >&2 "Error: Failed to source generate_feeds.sh from generate_authors.sh"; exit 1; }

_generate_author_pages_ram() {
    echo -e "${YELLOW}Processing author pages${NC}${ENABLE_AUTHOR_RSS:+" and RSS feeds"}...${NC}"

    local authors_index_data
    authors_index_data=$(ram_mode_get_dataset "authors_index")
    local main_authors_index_output="$OUTPUT_DIR/authors/index.html"

    mkdir -p "$OUTPUT_DIR/authors"

    if [ -z "$authors_index_data" ]; then
        echo -e "${YELLOW}No authors found in RAM index. Skipping author page generation.${NC}"
        return 0
    fi

    declare -A author_posts_by_slug=()
    declare -A author_name_by_slug=()
    declare -A author_email_by_slug=()
    local line author author_slug author_email
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS='|' read -r author author_slug author_email _ <<< "$line"
        [ -z "$author" ] && continue
        [ -z "$author_slug" ] && continue
        if [[ -z "${author_name_by_slug[$author_slug]+_}" ]]; then
            author_name_by_slug["$author_slug"]="$author"
            author_email_by_slug["$author_slug"]="$author_email"
        fi
        author_posts_by_slug["$author_slug"]+="$line"$'\n'
    done <<< "$authors_index_data"

    local author_slug_key
    for author_slug_key in $(printf '%s\n' "${!author_name_by_slug[@]}" | sort); do
        author="${author_name_by_slug[$author_slug_key]}"
        local author_data="${author_posts_by_slug[$author_slug_key]}"
        local author_page_html_file="$OUTPUT_DIR/authors/$author_slug_key/index.html"
        local author_rss_file="$OUTPUT_DIR/authors/$author_slug_key/${RSS_FILENAME:-rss.xml}"
        local author_page_rel_url="authors/${author_slug_key}/"
        local author_rss_rel_url="/authors/${author_slug_key}/${RSS_FILENAME:-rss.xml}"
        local post_count
        post_count=$(printf '%s\n' "$author_data" | awk 'NF { c++ } END { print c+0 }')

        mkdir -p "$(dirname "$author_page_html_file")"

        local author_page_content=""
        author_page_content+="<h1>${MSG_POSTS_BY:-Posts by} $author</h1>"$'\n'
        if [ "${ENABLE_AUTHOR_RSS:-false}" = true ]; then
            author_page_content+="<p><a href=\"$author_rss_rel_url\">${MSG_RSS_FEED:-RSS Feed}</a></p>"$'\n'
        fi
        author_page_content+="<div class=\"posts-list\">"$'\n'

        while IFS='|' read -r author_name_inner author_slug_inner author_email_inner post_title post_date post_lastmod post_filename post_slug post_image post_image_caption post_description; do
            [ -z "$post_title" ] && continue

            local post_url
            if [ -n "$post_date" ] && [[ "$post_date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                local year month day url_path
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
                url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
                url_path="${url_path//Year/$year}"
                url_path="${url_path//Month/$month}"
                url_path="${url_path//Day/$day}"
                url_path="${url_path//slug/$post_slug}"
                post_url="/$(echo "$url_path" | sed 's|^/||; s|/*$|/|')"
            else
                post_url="/$(echo "$post_slug" | sed 's|^/||; s|/*$|/|')"
            fi
            post_url="${BASE_URL}${post_url}"
            local formatted_date
            formatted_date=$(format_date "$post_date")

            author_page_content+="<article>"$'\n'
            author_page_content+="  <h2><a href=\"$post_url\">$post_title</a></h2>"$'\n'
            author_page_content+="  <div class=\"meta\">"$'\n'
            author_page_content+="    <time datetime=\"$post_date\">$formatted_date</time>"$'\n'
            author_page_content+="  </div>"$'\n'
            if [ -n "$post_description" ]; then
                author_page_content+="  <p class=\"summary\">$post_description</p>"$'\n'
            fi
            if [ -n "$post_image" ]; then
                author_page_content+="  <div class=\"author-image\">"$'\n'
                author_page_content+="    <img src=\"$post_image\" alt=\"$post_image_caption\" loading=\"lazy\">"$'\n'
                author_page_content+="  </div>"$'\n'
            fi
            author_page_content+="</article>"$'\n'
        done < <(printf '%s\n' "$author_data" | awk 'NF' | sort -t'|' -k5,5r)

        author_page_content+="</div>"$'\n'

        local page_title="${MSG_POSTS_BY:-Posts by} $author"
        local page_description="${MSG_POSTS_BY:-Posts by} $author - $post_count ${MSG_POSTS:-posts}"
        local header_content="$HEADER_TEMPLATE"
        local footer_content="$FOOTER_TEMPLATE"
        header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
        header_content=${header_content//\{\{page_title\}\}/"$page_title"}
        header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{og_description\}\}/"$page_description"}
        header_content=${header_content//\{\{twitter_description\}\}/"$page_description"}
        header_content=${header_content//\{\{og_type\}\}/"website"}
        header_content=${header_content//\{\{page_url\}\}/"$author_page_rel_url"}
        header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
        header_content=${header_content//\{\{og_image\}\}/}
        header_content=${header_content//\{\{twitter_image\}\}/}
        header_content=${header_content//<!-- bssg:tag_rss_link -->/}
        if [ "${ENABLE_AUTHOR_RSS:-false}" = true ]; then
            local author_rss_link="<link rel=\"alternate\" type=\"application/rss+xml\" title=\"$author RSS Feed\" href=\"$SITE_URL$author_rss_rel_url\">"
            header_content=${header_content//<!-- bssg:tag_rss_link -->/$author_rss_link}
        fi
        local schema_json
        schema_json="{\"@context\": \"https://schema.org\",\"@type\": \"CollectionPage\",\"name\": \"$page_title\",\"description\": \"$page_description\",\"url\": \"$SITE_URL$author_page_rel_url\",\"isPartOf\": {\"@type\": \"WebSite\",\"name\": \"$SITE_TITLE\",\"url\": \"$SITE_URL\"}}"
        header_content=${header_content//\{\{schema_json_ld\}\}/"<script type=\"application/ld+json\">$schema_json</script>"}

        local current_year
        current_year=$(date +%Y)
        footer_content=${footer_content//\{\{current_year\}\}/"$current_year"}
        footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}
        footer_content=${footer_content//\{\{all_rights_reserved\}\}/"${MSG_ALL_RIGHTS_RESERVED:-All rights reserved.}"}

        {
            echo "$header_content"
            echo "$author_page_content"
            echo "$footer_content"
        } > "$author_page_html_file"

        if [ "${ENABLE_AUTHOR_RSS:-false}" = true ]; then
            local author_post_data
            author_post_data=$(printf '%s\n' "$author_data" | awk 'NF' | sort -t'|' -k5,5r | awk -F'|' '{
                author_name = $1
                author_email = $3
                title = $4
                date = $5
                lastmod = $6
                filename = $7
                post_slug = $8
                image = $9
                image_caption = $10
                description = $11
                printf "%s|%s|%s|%s|%s||%s|%s|%s|%s|%s|%s\n", filename, filename, title, date, lastmod, post_slug, image, image_caption, description, author_name, author_email
            }')
            _generate_rss_feed "$author_rss_file" "$SITE_TITLE - ${MSG_POSTS_BY:-Posts by} $author" "${MSG_POSTS_BY:-Posts by} $author" "$author_page_rel_url" "$author_rss_rel_url" "$author_post_data"
        fi
    done

    local page_title="${MSG_ALL_AUTHORS:-All Authors}"
    local page_description="${MSG_ALL_AUTHORS:-All Authors} - $SITE_DESCRIPTION"
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"
    local main_content=""
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"$page_title"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$page_description"}
    header_content=${header_content//\{\{twitter_description\}\}/"$page_description"}
    header_content=${header_content//\{\{og_type\}\}/"website"}
    header_content=${header_content//\{\{page_url\}\}/"authors/"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    header_content=${header_content//\{\{og_image\}\}/}
    header_content=${header_content//\{\{twitter_image\}\}/}
    header_content=${header_content//<!-- bssg:tag_rss_link -->/}
    local schema_json
    schema_json="{\"@context\": \"https://schema.org\",\"@type\": \"CollectionPage\",\"name\": \"$page_title\",\"description\": \"List of all authors on $SITE_TITLE\",\"url\": \"$SITE_URL/authors/\",\"isPartOf\": {\"@type\": \"WebSite\",\"name\": \"$SITE_TITLE\",\"url\": \"$SITE_URL\"}}"
    header_content=${header_content//\{\{schema_json_ld\}\}/"<script type=\"application/ld+json\">$schema_json</script>"}
    local current_year
    current_year=$(date +%Y)
    footer_content=${footer_content//\{\{current_year\}\}/"$current_year"}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}
    footer_content=${footer_content//\{\{all_rights_reserved\}\}/"${MSG_ALL_RIGHTS_RESERVED:-All rights reserved.}"}

    main_content+="<h1>${MSG_ALL_AUTHORS:-All Authors}</h1>"$'\n'
    main_content+="<div class=\"tags-list\">"$'\n'
    for author_slug_key in $(printf '%s\n' "${!author_name_by_slug[@]}" | sort); do
        author="${author_name_by_slug[$author_slug_key]}"
        local post_count
        post_count=$(printf '%s\n' "${author_posts_by_slug[$author_slug_key]}" | awk 'NF { c++ } END { print c+0 }')
        if [ "$post_count" -gt 0 ]; then
            main_content+="    <a href=\"$BASE_URL/authors/$author_slug_key/\">$author <span class=\"tag-count\">($post_count)</span></a>"$'\n'
        fi
    done
    main_content+="</div>"$'\n'

    {
        echo "$header_content"
        echo "$main_content"
        echo "$footer_content"
    } > "$main_authors_index_output"

    echo -e "${GREEN}Author pages processed!${NC}"
    echo -e "${GREEN}Generated author list pages.${NC}"
}

# Generate author pages
generate_author_pages() {
    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        _generate_author_pages_ram
        return $?
    fi

    echo -e "${YELLOW}Processing author pages${NC}${ENABLE_AUTHOR_RSS:+" and RSS feeds"}...${NC}"

    local authors_index_file="$CACHE_DIR/authors_index.txt"
    local main_authors_index_output="$OUTPUT_DIR/authors/index.html"
    local modified_authors_list_file="${CACHE_DIR:-.bssg_cache}/modified_authors.list"

    # Check if the authors index file exists (needed for listing authors)
    if [ ! -f "$authors_index_file" ]; then
        echo -e "${YELLOW}Authors index file not found at $authors_index_file. Skipping author page generation.${NC}"
        # If the index doesn't exist, no authors were found in posts.
        # Ensure the main output directory exists but is empty.
        mkdir -p "$(dirname "$main_authors_index_output")"
        echo -e "${GREEN}Author pages processed! (No authors found)${NC}"
        echo -e "${GREEN}Generated author list pages. (No authors found)${NC}"
        return 0
    fi

    # --- Calculate Latest Common Dependency Time --- START ---
    # Get mtimes of config hash, templates, and locale file
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
    # --- Calculate Latest Common Dependency Time --- END ---

    # --- Simplified Global Check --- START ---
    # Decide if we need to proceed with any author generation steps at all.
    local proceed_with_generation=false
    local force_rebuild_status="${FORCE_REBUILD:-false}"

    if [ "$force_rebuild_status" = true ]; then
        proceed_with_generation=true
        echo "Force rebuild enabled, proceeding with author generation." >&2 # Debug
    elif [ "$latest_common_dep_time" -gt 0 ] && { [ ! -f "$main_authors_index_output" ] || (( $(get_file_mtime "$main_authors_index_output") < latest_common_dep_time )); }; then
        # Common dependencies are newer than the main output (or main output missing)
        proceed_with_generation=true
        echo "Common dependencies changed, proceeding with author generation." >&2 # Debug
    elif [ -s "$modified_authors_list_file" ]; then
        # Modified authors list exists and is not empty
        proceed_with_generation=true
        echo "Modified authors detected, proceeding with author generation." >&2 # Debug
    elif [ ! -f "$main_authors_index_output" ]; then
        # Fallback: if main output is missing, we should generate it
         proceed_with_generation=true
         echo "Main authors index missing, proceeding with author generation." >&2 # Debug
    fi

    if [ "$proceed_with_generation" = false ]; then
        echo -e "${GREEN}Authors index, author pages${NC}${ENABLE_AUTHOR_RSS:+, and author RSS feeds} appear up to date based on common dependencies and modified posts, skipping.${NC}"
        echo -e "${GREEN}Author pages processed!${NC}" # Keep consistent final message
        echo -e "${GREEN}Generated author list pages.${NC}" # Keep consistent final message
        return 0
    fi
    # --- Simplified Global Check --- END ---

    # --- Proceed with Generation ---

    # Get unique authors (Author|Slug pairs)
    local unique_authors_lines=$(awk -F'|' '{print $1 "|" $2}' "$authors_index_file" | sort | uniq)
    local author_count=$(echo "$unique_authors_lines" | grep -v '^$' | wc -l)
    echo -e "Checking ${GREEN}$author_count${NC} author pages${NC}${ENABLE_AUTHOR_RSS:+/feeds} for changes (based on common deps & modified authors)" # Updated message

    # --- Pre-group posts by author slug --- START ---
    local author_data_dir="$CACHE_DIR/author_data"
    rm -rf "$author_data_dir" # Clean previous data
    mkdir -p "$author_data_dir"
    echo -e "Pre-grouping posts by author into ${BLUE}$author_data_dir${NC}..."
    if awk -F'|' -v author_dir="$author_data_dir" '
        NF >= 2 { # Ensure at least author and slug fields exist
            author_slug = $2;
            if (author_slug != "") {
                # Sanitize slug just in case for filename safety? (basic: remove /)
                gsub(/\//, "_", author_slug);
                output_file = author_dir "/" author_slug ".tmp";
                print $0 >> output_file; # Append the whole line
                close(output_file); # Close file handle to avoid too many open files
            } else {
                print "Warning: Skipping line with empty author slug in authors_index: " $0 > "/dev/stderr";
            }
        }
    ' "$authors_index_file"; then
        echo -e "${GREEN}Pre-grouping complete.${NC}"
    else
        echo -e "${RED}Error: Failed to pre-group author data using awk.${NC}" >&2
        return 1
    fi
    # --- Pre-group posts by author slug --- END ---

    # Define a modified file_needs_rebuild function for parallel use
    parallel_file_needs_rebuild() {
        local output_file="$1"
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

    # Define a function to process a single author
    process_author() {
        local author_line="$1"
        local author_data_dir="$2"
        local latest_common_dep_time_for_author="$3"
        local modified_authors_file="$4" # Accept filename instead of hash

        # --- Load modified authors from file ---
        declare -A modified_authors_hash
        if [ -f "$modified_authors_file" ]; then
            local mod_author_local
            while IFS= read -r mod_author_local || [[ -n "$mod_author_local" ]]; do
                if [ -n "$mod_author_local" ]; then # Ensure not empty line
                    modified_authors_hash["$mod_author_local"]=1
                fi
            done < "$modified_authors_file"
        fi

        local author author_slug
        IFS='|' read -r author author_slug <<< "$author_line"

        if [ -n "$author" ]; then
            local author_page_html_file="$OUTPUT_DIR/authors/$author_slug/index.html"
            local author_rss_file="$OUTPUT_DIR/authors/$author_slug/${RSS_FILENAME:-rss.xml}"
            local author_page_rel_url="authors/${author_slug}/"
            local author_rss_rel_url="/authors/${author_slug}/${RSS_FILENAME:-rss.xml}"
            local rebuild_html=false
            local rebuild_rss=false

            # --- Force rebuild flags if author was modified ---
            local author_was_modified=false
            if [ -n "${modified_authors_hash[$author]}" ]; then
                author_was_modified=true
                rebuild_html=true # Force rebuild if author was modified
                if [ "${ENABLE_AUTHOR_RSS:-false}" = true ]; then
                     rebuild_rss=true # Force rebuild if author was modified
                fi
            fi

            # --- Check if HTML rebuild is needed ---
            if [ "$rebuild_html" = false ]; then
                if parallel_file_needs_rebuild "$author_page_html_file" "$latest_common_dep_time_for_author"; then
                    rebuild_html=true
                fi
            fi

            # --- Check if RSS rebuild is needed ---
            if [ "${ENABLE_AUTHOR_RSS:-false}" = true ] && [ "$rebuild_rss" = false ]; then
                if parallel_file_needs_rebuild "$author_rss_file" "$latest_common_dep_time_for_author"; then
                    rebuild_rss=true
                fi
            fi

            # --- Skip if no rebuilds needed ---
            if [ "$rebuild_html" = false ] && { [ "${ENABLE_AUTHOR_RSS:-false}" = false ] || [ "$rebuild_rss" = false ]; }; then
                echo "Author '$author' pages are up to date, skipping."
                return 0
            fi

            # --- Load author posts data ---
            local author_data_file="$author_data_dir/${author_slug}.tmp"
            if [ ! -f "$author_data_file" ]; then
                echo "Warning: No posts found for author '$author' (expected file: $author_data_file)" >&2
                return 0
            fi

            # Count posts for this author
            local post_count=$(wc -l < "$author_data_file")

            echo "Processing author '$author' ($post_count posts)..."

            # --- Generate Author HTML Page ---
            if [ "$rebuild_html" = true ]; then
                mkdir -p "$(dirname "$author_page_html_file")"

                # Generate author page content
                local author_page_content=""
                author_page_content+="<h1>${MSG_POSTS_BY:-Posts by} $author</h1>"$'\n'
                
                # Add RSS link if enabled
                if [ "${ENABLE_AUTHOR_RSS:-false}" = true ]; then
                    author_page_content+="<p><a href=\"$author_rss_rel_url\">${MSG_RSS_FEED:-RSS Feed}</a></p>"$'\n'
                fi

                # Add posts list
                author_page_content+="<div class=\"posts-list\">"$'\n'

                # Sort posts by date (newest first) and generate HTML
                local posts_html=""
                while IFS='|' read -r author_name author_slug_inner author_email post_title post_date post_lastmod post_filename post_slug post_image post_image_caption post_description; do
                    # Construct post URL using URL_SLUG_FORMAT (same logic as generate_posts.sh)
                    local post_url=""
                    if [ -n "$post_date" ]; then
                        local year month day
                        if [[ "$post_date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                            year="${BASH_REMATCH[1]}"
                            month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                            day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
                        else
                             year=$(date +%Y); month=$(date +%m); day=$(date +%d) # Fallback
                        fi
                        local url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
                        url_path="${url_path//Year/$year}"; url_path="${url_path//Month/$month}"; 
                        url_path="${url_path//Day/$day}"; url_path="${url_path//slug/$post_slug}"
                        # Ensure relative post_url starts with / and ends with /
                        post_url="/$(echo "$url_path" | sed 's|^/||; s|/*$|/|')"
                    else
                        # Fallback for posts without date
                        post_url="/$(echo "$post_slug" | sed 's|^/||; s|/*$|/|')"
                    fi
                    # Convert to full URL with BASE_URL
                    post_url="$BASE_URL$post_url"
                    local formatted_date=$(format_date "$post_date")
                    
                    posts_html+="<article>"$'\n'
                    posts_html+="  <h2><a href=\"$post_url\">$post_title</a></h2>"$'\n'
                    posts_html+="  <div class=\"meta\">"$'\n'
                    posts_html+="    <time datetime=\"$post_date\">$formatted_date</time>"$'\n'
                    posts_html+="  </div>"$'\n'
                    
                    if [ -n "$post_description" ]; then
                        posts_html+="  <p class=\"summary\">$post_description</p>"$'\n'
                    fi
                    
                    if [ -n "$post_image" ]; then
                        posts_html+="  <div class=\"author-image\">"$'\n'
                        posts_html+="    <img src=\"$post_image\" alt=\"$post_image_caption\" loading=\"lazy\">"$'\n'
                        posts_html+="  </div>"$'\n'
                    fi
                    
                    posts_html+="</article>"$'\n'
                done < <(sort -t'|' -k5,5r "$author_data_file")
                
                author_page_content+="$posts_html"

                author_page_content+="</div>"$'\n'

                # Generate full HTML page
                local page_title="${MSG_POSTS_BY:-Posts by} $author"
                local page_description="${MSG_POSTS_BY:-Posts by} $author - $post_count ${MSG_POSTS:-posts}"
                
                # Process templates with placeholder replacement
                local header_content="$HEADER_TEMPLATE"
                local footer_content="$FOOTER_TEMPLATE"

                # Replace placeholders in the header (following tags generator pattern)
                header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
                header_content=${header_content//\{\{page_title\}\}/"$page_title"}
                header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
                header_content=${header_content//\{\{og_description\}\}/"$page_description"}
                header_content=${header_content//\{\{twitter_description\}\}/"$page_description"}
                header_content=${header_content//\{\{og_type\}\}/"website"}
                header_content=${header_content//\{\{page_url\}\}/"$author_page_rel_url"}
                header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}

                # Remove unprocessed image placeholders
                header_content=${header_content//\{\{og_image\}\}/}
                header_content=${header_content//\{\{twitter_image\}\}/}

                # Remove the placeholder for the tag-specific RSS feed link
                header_content=${header_content//<!-- bssg:tag_rss_link -->/}

                # Add author RSS link if enabled
                if [ "${ENABLE_AUTHOR_RSS:-false}" = true ]; then
                    local author_rss_link="<link rel=\"alternate\" type=\"application/rss+xml\" title=\"$author RSS Feed\" href=\"$SITE_URL$author_rss_rel_url\">"
                    header_content=${header_content//<!-- bssg:tag_rss_link -->/$author_rss_link}
                fi

                # Schema.org structured data
                local schema_json="{\"@context\": \"https://schema.org\",\"@type\": \"CollectionPage\",\"name\": \"$page_title\",\"description\": \"$page_description\",\"url\": \"$SITE_URL$author_page_rel_url\",\"isPartOf\": {\"@type\": \"WebSite\",\"name\": \"$SITE_TITLE\",\"url\": \"$SITE_URL\"}}"
                header_content=${header_content//\{\{schema_json_ld\}\}/"<script type=\"application/ld+json\">$schema_json</script>"}

                # Replace placeholders in the footer
                local current_year=$(date +%Y)
                footer_content=${footer_content//\{\{current_year\}\}/"$current_year"}
                footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}
                footer_content=${footer_content//\{\{all_rights_reserved\}\}/"${MSG_ALL_RIGHTS_RESERVED:-All rights reserved.}"}

                # Create the full HTML page
                {
                    echo "$header_content"
                    echo "$author_page_content"
                    echo "$footer_content"
                } > "$author_page_html_file"

                echo "Generated author page: $author_page_html_file"
            fi

            # --- Generate Author RSS Feed ---
            if [ "${ENABLE_AUTHOR_RSS:-false}" = true ] && [ "$rebuild_rss" = true ]; then
                mkdir -p "$(dirname "$author_rss_file")"
                
                # Generate RSS feed for this author
                local rss_title="$SITE_TITLE - ${MSG_POSTS_BY:-Posts by} $author"
                local rss_description="${MSG_POSTS_BY:-Posts by} $author"
                local feed_link_rel="$author_page_rel_url"
                local feed_atom_link_rel="$author_rss_rel_url"
                
                # Read and format author post data for RSS generation
                local author_post_data=""
                if [ -f "$author_data_file" ]; then
                    # Transform author data format to RSS format and sort by date (newest first)
                    # Author format: Author|Slug|Email|Title|Date|LastMod|Filename|PostSlug|Image|ImageCaption|Description
                    # RSS format:    file|filename|title|date|lastmod|tags|slug|image|image_caption|description|author_name|author_email
                    author_post_data=$(sort -t'|' -k5,5r "$author_data_file" | awk -F'|' '{
                        # Map fields from author format to RSS format
                        author_name = $1
                        author_slug = $2
                        author_email = $3
                        title = $4
                        date = $5
                        lastmod = $6
                        filename = $7
                        post_slug = $8
                        image = $9
                        image_caption = $10
                        description = $11
                        
                        # RSS format: file|filename|title|date|lastmod|tags|slug|image|image_caption|description|author_name|author_email
                        printf "%s|%s|%s|%s|%s||%s|%s|%s|%s|%s|%s\n", filename, filename, title, date, lastmod, post_slug, image, image_caption, description, author_name, author_email
                    }')
                fi
                
                # Check if _generate_rss_feed function exists
                if ! command -v _generate_rss_feed > /dev/null 2>&1; then
                    echo -e "${RED}Error: _generate_rss_feed function not found. Ensure generate_feeds.sh is sourced correctly.${NC}" >&2
                else
                    _generate_rss_feed "$author_rss_file" "$rss_title" "$rss_description" "$feed_link_rel" "$feed_atom_link_rel" "$author_post_data"
                    echo "Generated author RSS feed: $author_rss_file"
                fi
            fi
        fi
    }

    # Export the function for potential parallel use
    export -f process_author parallel_file_needs_rebuild

    # Process each unique author
    echo "$unique_authors_lines" | while IFS= read -r author_line || [[ -n "$author_line" ]]; do
        if [ -n "$author_line" ]; then
            process_author "$author_line" "$author_data_dir" "$latest_common_dep_time" "$modified_authors_list_file"
        fi
    done

    # --- Generate Main Authors Index Page ---
    if [ "${AUTHORS_INDEX_NEEDS_REBUILD:-false}" = true ] || [ ! -f "$main_authors_index_output" ] || (( $(get_file_mtime "$main_authors_index_output") < latest_common_dep_time )); then
        echo "Generating main authors index page..."
        mkdir -p "$(dirname "$main_authors_index_output")"

        # Count posts per author and generate the main index
        local authors_with_counts=""
        echo "$unique_authors_lines" | while IFS= read -r author_line || [[ -n "$author_line" ]]; do
            if [ -n "$author_line" ]; then
                local author author_slug
                IFS='|' read -r author author_slug <<< "$author_line"
                local author_data_file="$author_data_dir/${author_slug}.tmp"
                if [ -f "$author_data_file" ]; then
                    local post_count=$(wc -l < "$author_data_file")
                    echo "$author|$author_slug|$post_count"
                fi
            fi
        done | sort > "${CACHE_DIR}/authors_with_counts.tmp"

        # Generate main authors index HTML
        local main_content=""
        main_content+="<h1>${MSG_ALL_AUTHORS:-All Authors}</h1>"$'\n'
        main_content+="<div class=\"tags-list\">"$'\n' # Reuse tags styling

        while IFS='|' read -r author author_slug post_count; do
            if [ -n "$author" ] && [ "$post_count" -gt 0 ]; then
                main_content+="    <a href=\"$BASE_URL/authors/$author_slug/\">$author <span class=\"tag-count\">($post_count)</span></a>"$'\n'
            fi
        done < "${CACHE_DIR}/authors_with_counts.tmp"

        main_content+="</div>"$'\n'

        # Generate full HTML page for main authors index
        local page_title="${MSG_ALL_AUTHORS:-All Authors}"
        local page_description="${MSG_ALL_AUTHORS:-All Authors} - $SITE_DESCRIPTION"
        local authors_index_rel_url="authors/"
        
        # Process templates with placeholder replacement (following tags generator pattern)
        local header_content="$HEADER_TEMPLATE"
        local footer_content="$FOOTER_TEMPLATE"

        # Replace placeholders in the header
        header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
        header_content=${header_content//\{\{page_title\}\}/"$page_title"}
        header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
        header_content=${header_content//\{\{og_description\}\}/"$page_description"}
        header_content=${header_content//\{\{twitter_description\}\}/"$page_description"}
        header_content=${header_content//\{\{og_type\}\}/"website"}
        header_content=${header_content//\{\{page_url\}\}/"$authors_index_rel_url"}
        header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}

        # Remove unprocessed image placeholders
        header_content=${header_content//\{\{og_image\}\}/}
        header_content=${header_content//\{\{twitter_image\}\}/}

        # Remove the placeholder for the tag-specific RSS feed link in the main authors index
        header_content=${header_content//<!-- bssg:tag_rss_link -->/}

        # Schema.org structured data
        local schema_json="{\"@context\": \"https://schema.org\",\"@type\": \"CollectionPage\",\"name\": \"$page_title\",\"description\": \"List of all authors on $SITE_TITLE\",\"url\": \"$SITE_URL/authors/\",\"isPartOf\": {\"@type\": \"WebSite\",\"name\": \"$SITE_TITLE\",\"url\": \"$SITE_URL\"}}"
        header_content=${header_content//\{\{schema_json_ld\}\}/"<script type=\"application/ld+json\">$schema_json</script>"}

        # Replace placeholders in the footer
        local current_year=$(date +%Y)
        footer_content=${footer_content//\{\{current_year\}\}/"$current_year"}
        footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}
        footer_content=${footer_content//\{\{all_rights_reserved\}\}/"${MSG_ALL_RIGHTS_RESERVED:-All rights reserved.}"}

        {
            echo "$header_content"
            echo "$main_content"
            echo "$footer_content"
        } > "$main_authors_index_output"

        echo "Generated main authors index: $main_authors_index_output"
        
        # Clean up temporary file
        rm -f "${CACHE_DIR}/authors_with_counts.tmp"
    else
        echo "Main authors index is up to date, skipping..."
    fi

    # Clean up author data directory
    rm -rf "$author_data_dir"

    echo -e "${GREEN}Author pages processed!${NC}"
    echo -e "${GREEN}Generated author list pages.${NC}"
} 
