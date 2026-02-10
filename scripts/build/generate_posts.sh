#!/usr/bin/env bash
#
# BSSG - Post Generation
# Functions for converting markdown posts to HTML.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_posts.sh"; exit 1; }
# shellcheck source=content.sh disable=SC1091
source "$(dirname "$0")/content.sh" || { echo >&2 "Error: Failed to source content.sh from generate_posts.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_posts.sh"; exit 1; } # For file_needs_rebuild checks etc.
# shellcheck source=related_posts.sh disable=SC1091
source "$(dirname "$0")/related_posts.sh" || { echo >&2 "Error: Failed to source related_posts.sh from generate_posts.sh"; exit 1; } # For related posts functionality

# --- Post Generation Functions --- START ---

declare -gA BSSG_POST_ISO8601_CACHE=()

format_iso8601_post_date() {
    local input_dt="$1"
    local iso_dt=""

    if [ -z "$input_dt" ]; then
        echo ""
        return
    fi

    local cache_key="${TIMEZONE:-local}|${input_dt}"
    if [[ "$(declare -p BSSG_POST_ISO8601_CACHE 2>/dev/null || true)" != "declare -A"* ]]; then
        unset BSSG_POST_ISO8601_CACHE 2>/dev/null || true
        declare -gA BSSG_POST_ISO8601_CACHE=()
    fi
    if [[ -n "${BSSG_POST_ISO8601_CACHE[$cache_key]+_}" ]]; then
        echo "${BSSG_POST_ISO8601_CACHE[$cache_key]}"
        return
    fi

    # Handle "now" separately
    if [ "$input_dt" = "now" ]; then
        iso_dt=$(LC_ALL=C date +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
    else
        # Try parsing different formats based on OS
        if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
            # Format 1: YYYY-MM-DD HH:MM:SS ZZZZ (e.g., +0200)
            iso_dt=$(LC_ALL=C date -j -f "%Y-%m-%d %H:%M:%S %z" "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
            # Format 2: YYYY-MM-DD HH:MM:SS
            [ -z "$iso_dt" ] && iso_dt=$(LC_ALL=C date -j -f "%Y-%m-%d %H:%M:%S" "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
            # Format 3: YYYY-MM-DD (assume T00:00:00)
            [ -z "$iso_dt" ] && iso_dt=$(LC_ALL=C date -j -f "%Y-%m-%d" "$input_dt" +"%Y-%m-%dT00:00:00%z" 2>/dev/null)
            # Format 4: RFC 2822 subset (e.g., 07 Sep 2023 08:10:00 +0200)
            [ -z "$iso_dt" ] && iso_dt=$(LC_ALL=C date -j -f "%d %b %Y %H:%M:%S %z" "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
        else
            # GNU date -d handles many formats.
            iso_dt=$(LC_ALL=C date -d "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
        fi
    fi

    # Normalize timezone from +0000 to Z and +hhmm to +hh:mm.
    if [ -n "$iso_dt" ] && [[ "$iso_dt" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
        local tz_offset="${BASH_REMATCH[0]}"
        local tz_hh="${BASH_REMATCH[1]}"
        local tz_mm="${BASH_REMATCH[2]}"
        if [ "$tz_hh" = "+00" ] && [ "$tz_mm" = "00" ]; then
            iso_dt="${iso_dt%$tz_offset}Z"
        else
            iso_dt="${iso_dt%$tz_offset}${tz_hh}:${tz_mm}"
        fi
    fi

    BSSG_POST_ISO8601_CACHE["$cache_key"]="$iso_dt"
    echo "$iso_dt"
}

# Convert markdown to HTML
convert_markdown() {
    local input_file="$1"
    local output_base_path="$2"
    local title="$3"
    local date="$4"
    local lastmod="$5"
    local tags="$6"
    local slug="$7"
    local image="$8"
    local image_caption="$9"
    local description="${10}"
    local author_name="${11}"
    local author_email="${12}"
    local skip_rebuild_check="${13:-false}"
    
    local content_cache_file="${CACHE_DIR:-.bssg_cache}/content/$(basename "$input_file")"
    local output_html_file="$output_base_path/index.html"
    local ram_mode_active=false
    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$input_file"; then
        ram_mode_active=true
    fi

    # Check if the source file exists
    if ! $ram_mode_active && [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: Source file '$input_file' not found${NC}" >&2
        return 1
    fi

    # Skip if output file is newer than input file and no force rebuild.
    # When callers already prefiltered rebuild candidates, this check can be skipped.
    if [ "$skip_rebuild_check" != true ]; then
        if ! file_needs_rebuild "$input_file" "$output_html_file"; then
            echo -e "Skipping unchanged file: ${YELLOW}$(basename "$input_file")${NC}"
            return 0
        fi
    fi

    if [ "${BSSG_RAM_MODE:-false}" != true ] || [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
        echo -e "Processing post: ${GREEN}$(basename "$input_file")${NC}"
    fi

    # Extract body content (without frontmatter) in one awk pass.
    # This is materially faster than line-by-line bash parsing on large markdown files.
    local content=""
    local source_stream=""
    if $ram_mode_active; then
        source_stream=$(ram_mode_get_content "$input_file")
    else
        source_stream=$(cat "$input_file")
    fi
    content=$(printf '%s' "$source_stream" | awk '
        NR == 1 {
            if ($0 == "---") {
                has_frontmatter = 1
                in_frontmatter = 1
                next
            }
        }

        {
            if (has_frontmatter) {
                if (in_frontmatter) {
                    if ($0 == "---") {
                        in_frontmatter = 0
                    }
                    next
                }
                print
            } else {
                print
            }
        }
    ')
    
    # Cache the markdown content *without frontmatter* for potential use in RSS full content
    if ! $ram_mode_active && [ -n "$CACHE_DIR" ] && [ -d "${CACHE_DIR}/content" ]; then
        # Write the $content variable (which has frontmatter removed) to the cache file
        lock_file "$content_cache_file"
        printf '%s' "$content" > "$content_cache_file"
        unlock_file "$content_cache_file"
    fi

    # Calculate reading time
    local reading_time
    reading_time=$(calculate_reading_time "$content")

    # Convert markdown content to HTML (No HTML caching here anymore)
    local html_content
    if [[ "$input_file" == *.html ]]; then
        # For HTML files, extract content between <body> tags (simple approach)
        # Assumes content is already HTML
        html_content=$(sed -n '/<body.*>/,/<\/body>/p' "$input_file" | sed '1d;$d')
        # echo -e "Extracted body content from HTML file: ${GREEN}$(basename "$input_file")${NC}" # Can be verbose
    elif [[ "$input_file" == *.md ]]; then
        # Original Markdown conversion using the raw content we extracted/cached
        # This now uses the content *without* frontmatter
        html_content=$(convert_markdown_to_html "$content")
        if [ $? -ne 0 ]; then
            echo -e "${RED}Markdown conversion failed for '$input_file', skipping html generation.${NC}" >&2
            # Optionally delete the output file if it exists from a previous run?
            # rm -f "$output_html_file"
            return 1
        fi
    else
        echo -e "${RED}Error: Unknown input file type '$input_file' for content conversion.${NC}" >&2
        return 1
    fi

    # Create HTML tags for tags
    local tags_html=""
    if [ -n "$tags" ]; then
        tags_html="<div class=\"tags\">"
        IFS=',' read -ra TAG_ARRAY <<< "$tags"
        for tag in "${TAG_ARRAY[@]}"; do
            tag=$(echo "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -z "$tag" ]] && continue
            local tag_slug=$(echo "$tag" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /-/g' -e 's/[^a-z0-9-]//g')
            if [[ -n "$tag_slug" ]]; then # Ensure tag slug is not empty
                tags_html+=" <a href=\"${SITE_URL:-}/tags/${tag_slug}/\" class=\"tag\">${tag}</a>"
            fi
        done
        tags_html+="</div>"
    fi

    # Use pre-loaded templates
    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"

    # Verify templates are not empty
    if [ -z "$header_content" ] || [ -z "$footer_content" ]; then
        echo -e "${RED}Error: Header or Footer template is empty. Was templates.sh sourced correctly?${NC}" >&2
        return 1
    fi

    # Replace placeholders in the header
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"$title"}
    header_content=${header_content//\{\{og_type\}\}/"article"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}

    # Construct page URL based on format
    local page_url=""
    if [ -n "$date" ]; then
        local year month day
        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
            year="${BASH_REMATCH[1]}"
            month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
            day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
        else
             year=$(date +%Y); month=$(date +%m); day=$(date +%d) # Fallback
        fi
        local url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
        url_path="${url_path//Year/$year}"; url_path="${url_path//Month/$month}"; 
        url_path="${url_path//Day/$day}"; url_path="${url_path//slug/$slug}"
        # Ensure relative page_url starts with / and ends with /
        page_url="/$(echo "$url_path" | sed 's|^/||; s|/*$|/|')"
    else
        # Ensure relative page_url starts with / and ends with / for slug-only urls
        page_url="/$(echo "$slug" | sed 's|^/||; s|/*$|/|')"
    fi
    header_content=${header_content//\{\{page_url\}\}/"$page_url"}

    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    # Trim whitespace from post description
    local meta_desc
    meta_desc=$(echo "${description:-$SITE_DESCRIPTION}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    header_content=${header_content//\{\{og_description\}\}/"$meta_desc"}
    header_content=${header_content//\{\{twitter_description\}\}/"$meta_desc"}

    # Generate Schema.org JSON-LD for articles
    local schema_json_ld=""
    if [ -n "$date" ]; then
        local iso_date iso_lastmod_date

        iso_date=$(format_iso8601_post_date "$date")
        # Use date as fallback for lastmod, then format
        iso_lastmod_date=$(format_iso8601_post_date "${lastmod:-$date}")
        # If lastmod still empty, use iso_date as fallback
        [ -z "$iso_lastmod_date" ] && iso_lastmod_date="$iso_date"

        # Fallback to build time if both are empty (should be rare)
        if [ -z "$iso_date" ]; then
            local now_iso
            now_iso=$(format_iso8601_post_date "now")
            iso_date="$now_iso"
            iso_lastmod_date="$now_iso"
        fi

        local image_url=""
        if [ -n "$image" ]; then
             image_url=$(fix_url "$image")
        fi

        # Create JSON-LD using post-specific author info
        local post_author_name="${author_name:-${AUTHOR_NAME:-Anonymous}}"
        local post_author_email="${author_email:-${AUTHOR_EMAIL:-anonymous@example.com}}"
        
        # Build author JSON - only include email if it's provided
        local author_json
        if [ -n "$author_email" ]; then
            author_json=$(printf '{\n    "@type": "Person",\n    "name": "%s",\n    "email": "%s"\n  }' "$post_author_name" "$post_author_email")
        else
            author_json=$(printf '{\n    "@type": "Person",\n    "name": "%s"\n  }' "$post_author_name")
        fi
        
        schema_json_ld=$(printf '<script type="application/ld+json">\n{\n  "@context": "https://schema.org",\n  "@type": "Article",\n  "headline": "%s",\n  "datePublished": "%s",\n  "dateModified": "%s",\n  "author": %s,\n  "publisher": {\n    "@type": "Organization",\n    "name": "%s",\n    "logo": {\n      "@type": "ImageObject",\n      "url": "%s/logo.png"\n    }\n  },\n  "description": "%s",\n  "mainEntityOfPage": {\n    "@type": "WebPage",\n    "@id": "%s%s"\n  }%s\n}\n</script>' \
          "$(echo "$title" | sed 's/"/\"/g')" \
          "$iso_date" \
          "$iso_lastmod_date" \
          "$author_json" \
          "$SITE_TITLE" \
          "$SITE_URL" \
          "$(echo "$meta_desc" | sed 's/"/\"/g')" \
          "$SITE_URL" "$page_url" \
          "${image_url:+,
  \"image\": {
    \"@type\": \"ImageObject\",
    \"url\": \"$image_url\"
  }}")
    fi
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}

    # Handle image placeholders
    if [ -n "$image_url" ]; then
        local og_image_tag="<meta property=\"og:image\" content=\"$image_url\">"
        local twitter_image_tag="<meta name=\"twitter:image\" content=\"$image_url\">"
        header_content=${header_content//\{\{og_image\}\}/"$og_image_tag"}
        header_content=${header_content//\{\{twitter_image\}\}/"$twitter_image_tag"}
    else
        header_content=${header_content//\{\{og_image\}\}/}
        header_content=${header_content//\{\{twitter_image\}\}/}
    fi

    # Construct meta div (date, reading time, lastmod)
    # Determine the date format based on SHOW_TIMEZONE
    local display_date_format="$DATE_FORMAT"
    if [ "${SHOW_TIMEZONE:-false}" = false ]; then
        # Remove timezone format specifiers (%z or %Z) if they exist
        display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
    fi

    local formatted_date=$(format_date "$date" "$display_date_format")
    local formatted_lastmod=$(format_date "$lastmod" "$display_date_format")
    local post_meta_reading_time
    post_meta_reading_time=$(printf "${MSG_READING_TIME_TEMPLATE:-%d min read}" "$reading_time")
    local display_author_name="${author_name:-${AUTHOR_NAME:-Anonymous}}"
    local post_meta="<div class=\"page-meta\">"
    post_meta+="<p class=\"meta\">"
    post_meta+="${MSG_PUBLISHED_ON:-Published on}: <time datetime=\"$date\">$formatted_date</time> ${MSG_BY:-by} <strong>$display_author_name</strong>"
    post_meta+="</p>"
    if [ "$formatted_date" != "$formatted_lastmod" ]; then
        post_meta+="<p class=\"meta reading-time\">"
        post_meta+="${MSG_UPDATED_ON:-Updated on}: <time datetime=\"$lastmod\">$formatted_lastmod</time> &bull; $post_meta_reading_time"
        post_meta+="</p>"
    else
        post_meta+="<p class=\"meta reading-time\">$post_meta_reading_time</p>"
    fi
    post_meta+="</div>"
    
    # Construct featured image HTML
    local image_html=""
    if [ -n "$image" ]; then
        local alt_text="${image_caption:-$title}"
        image_html="<div class=\"featured-image\"><img src=\"$(fix_url "$image")\" alt=\"$alt_text\"><div class=\"image-caption\">${image_caption:-$title}</div></div>"
    fi
    
    # Generate related posts if enabled and tags exist
    local related_posts_html=""
    if [ "${ENABLE_RELATED_POSTS:-true}" = true ] && [ -n "$tags" ]; then
        # RAM fast path: direct map lookup avoids per-post command-substitution/function overhead.
        if [ "${BSSG_RAM_MODE:-false}" = true ] && \
           [ "${BSSG_RAM_RELATED_POSTS_READY:-false}" = true ] && \
           [ "${BSSG_RAM_RELATED_POSTS_LIMIT:-}" = "${RELATED_POSTS_COUNT:-3}" ]; then
            related_posts_html="${BSSG_RAM_RELATED_POSTS_HTML[$slug]-}"
            if [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
                echo -e "${BLUE}DEBUG: Generating related posts for $slug with tags: $tags${NC}"
            fi
        else
            if [ "${BSSG_RAM_MODE:-false}" != true ] || [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
                echo -e "${BLUE}DEBUG: Generating related posts for $slug with tags: $tags${NC}"
            fi
            related_posts_html=$(generate_related_posts "$slug" "$tags" "$date" "${RELATED_POSTS_COUNT:-3}")
        fi
    else
        if [ "${BSSG_RAM_MODE:-false}" != true ] || [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
            echo -e "${BLUE}DEBUG: Skipping related posts for $slug - ENABLE_RELATED_POSTS=${ENABLE_RELATED_POSTS:-true}, tags=$tags${NC}"
        fi
    fi
    
    # Construct article body
    local final_html="${header_content}"
    final_html+='<article class="post">'$'\n'
    final_html+="  <h1>$title</h1>"$'\n'
    final_html+="$post_meta"$'\n'
    final_html+="$image_html"$'\n'
    final_html+="$html_content"$'\n'
    final_html+="$tags_html"$'\n'
    if [ -n "$related_posts_html" ]; then
        final_html+="$related_posts_html"$'\n'
    fi
    final_html+='</article>'$'\n'

    # Replace placeholders in footer content
    local current_year=$(date +'%Y')
    local post_author_name="${author_name:-${AUTHOR_NAME:-Anonymous}}"
    footer_content=${footer_content//\{\{current_year\}\}/$current_year}
    footer_content=${footer_content//\{\{author_name\}\}/$post_author_name}

    final_html+="${footer_content}"

    # Create output directory
    mkdir -p "$output_base_path"

    # Write the final HTML
    printf '%s' "$final_html" > "$output_html_file"
    local write_status=$?
    if [ $write_status -ne 0 ]; then
        echo "${RED}ERROR:${NC} Failed to write HTML file '$output_html_file' (Status: $write_status)" >&2
        return 1
    fi

    return 0
}

# Process all markdown files listed in the file index
process_all_markdown_files() {
    echo -e "${YELLOW}Processing markdown posts...${NC}"

    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local modified_tags_list="${CACHE_DIR:-.bssg_cache}/modified_tags.list" # Define path for modified tags
    local modified_authors_list="${CACHE_DIR:-.bssg_cache}/modified_authors.list" # Define path for modified authors
    local file_index_prev="${CACHE_DIR:-.bssg_cache}/file_index_prev.txt" # Path to previous index
    local ram_mode_active=false
    local file_index_data=""
    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        ram_mode_active=true
        file_index_data=$(ram_mode_get_dataset "file_index")
    fi

    if ! $ram_mode_active && [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index not found at '$file_index'. Run indexing first.${NC}" >&2
        return 1
    fi

    local total_file_count=0
    if $ram_mode_active; then
        total_file_count=$(printf '%s\n' "$file_index_data" | awk 'NF { c++ } END { print c+0 }')
    else
        total_file_count=$(wc -l < "$file_index")
    fi
    if [ "$total_file_count" -eq 0 ]; then
        echo -e "${YELLOW}No posts found in file index. Skipping post generation.${NC}"
        return 0
    fi
    echo -e "Checking ${GREEN}$total_file_count${NC} potential posts listed in index."

    # --- OPTIMIZATION: Quick check if any posts need rebuilding ---
    local needs_pass1=false
    local posts_needing_rebuild=0

    # Only do expensive Pass 1 if related posts are enabled AND posts might need rebuilding
    if [ "${ENABLE_RELATED_POSTS:-true}" = true ] && ! $ram_mode_active; then
        echo -e "${BLUE}DEBUG: Related posts enabled, starting quick scan...${NC}"
        # Quick scan to see if ANY posts need rebuilding before doing expensive Pass 1
        echo -e "${YELLOW}Quick scan: Checking if any posts need rebuilding...${NC}"
        
        while IFS= read -r line; do
            local file filename title date lastmod tags slug image image_caption description author_name author_email
            IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email <<< "$line"

            # Basic check if it looks like a post
            if [ -z "$date" ] || [[ "$file" != "$SRC_DIR"* ]]; then
                continue
            fi

            # Calculate expected output path
            local year month day
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                year=$(date +%Y); month=$(date +%m); day=$(date +%d)
            fi
            local url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
            url_path="${url_path//Year/$year}"; url_path="${url_path//Month/$month}";
            url_path="${url_path//Day/$day}"; url_path="${url_path//slug/$slug}"
            local output_html_file="${OUTPUT_DIR:-output}/$url_path/index.html"

            # Quick rebuild check
            common_rebuild_check "$output_html_file"
            local common_result=$?
            local needs_rebuild=false

            if [ $common_result -eq 0 ]; then
                needs_rebuild=true
            else
                local input_time=$(get_file_mtime "$file")
                local output_time=$(get_file_mtime "$output_html_file")
                if (( input_time > output_time )); then
                    needs_rebuild=true
                fi
            fi

            if $needs_rebuild; then
                posts_needing_rebuild=$((posts_needing_rebuild + 1))
                needs_pass1=true
                # Early exit optimization: if we find posts needing rebuild, we need Pass 1
                break
            fi
        done < <(
            if $ram_mode_active; then
                printf '%s\n' "$file_index_data" | awk 'NF'
            else
                cat "$file_index"
            fi
        )
        
        echo -e "Quick scan result: ${GREEN}$posts_needing_rebuild${NC} posts need rebuilding"
    fi

    # --- PASS 1: Only run if needed (posts need rebuilding AND related posts enabled) ---
    if [ "$needs_pass1" = true ] && [ "${ENABLE_RELATED_POSTS:-true}" = true ] && ! $ram_mode_active; then
        echo -e "${BLUE}DEBUG: Both needs_pass1=true and ENABLE_RELATED_POSTS=true, running Pass 1...${NC}"
        echo -e "${YELLOW}Pass 1: Identifying modified tags for related posts cache invalidation...${NC}"
        
        # Clear previous modified tags lists
        rm -f "$modified_tags_list"
        rm -f "$modified_authors_list"
        touch "$modified_tags_list" # Ensure file exists even if empty
        touch "$modified_authors_list" # Ensure file exists even if empty
        
        while IFS= read -r line; do
            local file filename title date lastmod tags slug image image_caption description author_name author_email
            IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email <<< "$line"

            # Basic check if it looks like a post
            if [ -z "$date" ] || [[ "$file" != "$SRC_DIR"* ]]; then
                continue
            fi

            # Calculate expected output path
            local year month day
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                year=$(date +%Y); month=$(date +%m); day=$(date +%d)
            fi
            local url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
            url_path="${url_path//Year/$year}"; url_path="${url_path//Month/$month}";
            url_path="${url_path//Day/$day}"; url_path="${url_path//slug/$slug}"
            local output_html_file="${OUTPUT_DIR:-output}/$url_path/index.html"

            # Perform the rebuild check here
            common_rebuild_check "$output_html_file"
            local common_result=$?
            local needs_rebuild=false

            if [ $common_result -eq 0 ]; then
                needs_rebuild=true # Common checks failed (config changed, template newer, output missing)
            else # common_result is 2 (output exists and newer than templates/locale)
                local input_time=$(get_file_mtime "$file")
                local output_time=$(get_file_mtime "$output_html_file")
                if (( input_time > output_time )); then
                    needs_rebuild=true # Input file is newer
                fi
            fi

            # If post needs rebuilding, add its tags to the modified list
            if $needs_rebuild; then
                local new_tags="$tags"
                local old_tags=""
                # Try to get old tags from the previous index snapshot
                if [ -f "$file_index_prev" ]; then
                    old_tags=$(grep "^${file}|" "$file_index_prev" | cut -d'|' -f6)
                fi
                
                # Combine old and new tags
                local combined_tags="${old_tags},${new_tags}"
                
                if [ -n "$combined_tags" ]; then
                    # Split by comma, trim, filter empty, sort unique, and add each tag on a new line
                    echo "$combined_tags" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep . | sort -u >> "$modified_tags_list"
                fi

                # Track modified authors (similar logic to tags)
                local new_author="$author_name"
                local old_author=""
                if [ -f "$file_index_prev" ]; then
                    old_author=$(grep "^${file}|" "$file_index_prev" | cut -d'|' -f11)
                fi
                
                # Add both old and new authors to the modified list (if they exist)
                if [ -n "$old_author" ] && [ "$old_author" != "" ]; then
                    echo "$old_author" >> "$modified_authors_list"
                fi
                if [ -n "$new_author" ] && [ "$new_author" != "" ]; then
                    echo "$new_author" >> "$modified_authors_list"
                fi
            fi
        done < "$file_index"

        # Unique sort the modified tags and authors lists
        if [ -f "$modified_tags_list" ]; then
            local temp_tags_list=$(mktemp)
            sort -u "$modified_tags_list" > "$temp_tags_list"
            mv "$temp_tags_list" "$modified_tags_list"
        fi
        
        if [ -f "$modified_authors_list" ]; then
            local temp_authors_list=$(mktemp)
            sort -u "$modified_authors_list" > "$temp_authors_list"
            mv "$temp_authors_list" "$modified_authors_list"
        fi

        # Invalidate related posts cache if there are modified tags
        if [ -f "$modified_tags_list" ] && [ -s "$modified_tags_list" ]; then
            # Source related posts functions if not already loaded
            if ! command -v invalidate_related_posts_cache_for_tags > /dev/null 2>&1; then
                # shellcheck source=related_posts.sh disable=SC1091
                source "$(dirname "$0")/related_posts.sh" || { echo -e "${RED}Error: Failed to source related_posts.sh${NC}"; exit 1; }
            fi
            
            # Create a temporary file to capture the list of invalidated posts
            RELATED_POSTS_INVALIDATED_LIST="${CACHE_DIR:-.bssg_cache}/related_posts_invalidated.list"
            > "$RELATED_POSTS_INVALIDATED_LIST"  # Create empty file
            
            # Call the invalidation function with the output file
            invalidate_related_posts_cache_for_tags "$modified_tags_list" "$RELATED_POSTS_INVALIDATED_LIST"
            
            # Export the list for use in pass 2
            export RELATED_POSTS_INVALIDATED_LIST
        fi
    elif $ram_mode_active; then
        echo -e "${BLUE}DEBUG: RAM mode active, skipping Pass 1 related-posts invalidation (in-memory computation).${NC}"
    else
        echo -e "${BLUE}DEBUG: Pass 1 skipped - needs_pass1=$needs_pass1, ENABLE_RELATED_POSTS=${ENABLE_RELATED_POSTS:-true}${NC}"
    fi

    # --- PASS 2: Process posts with proper rebuild flags ---
    echo -e "${YELLOW}Pass 2: Processing posts...${NC}"

    # Pre-filter files that need rebuilding
    local files_to_process_list=()
    local files_to_process_count=0
    local skipped_count=0

    if $ram_mode_active && [ "${FORCE_REBUILD:-false}" = true ]; then
        echo -e "RAM mode force rebuild: skipping per-post rebuild checks."
        while IFS= read -r line; do
            local file filename title date
            IFS='|' read -r file filename _ date _ <<< "$line"
            if [ -n "$date" ] && [[ "$file" == "$SRC_DIR"* ]]; then
                files_to_process_list+=("$line")
                files_to_process_count=$((files_to_process_count + 1))
            fi
        done < <(printf '%s\n' "$file_index_data" | awk 'NF')
    else
        while IFS= read -r line; do
            local file filename title date lastmod tags slug image image_caption description author_name author_email
            IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email <<< "$line"

            # Basic check if it looks like a post
            if [ -z "$date" ] || [[ "$file" != "$SRC_DIR"* ]]; then
                 # echo -e "Skipping non-post file listed in index (pre-check): ${YELLOW}$file${NC}" >&2 # Too verbose
                 continue
            fi

            # Calculate expected output path (logic copied from process_single_file)
            local output_path
            local year month day
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                year=$(date +%Y); month=$(date +%m); day=$(date +%d)
            fi
            local url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
            url_path="${url_path//Year/$year}"; url_path="${url_path//Month/$month}";
            url_path="${url_path//Day/$day}"; url_path="${url_path//slug/$slug}"
            local output_html_file="${OUTPUT_DIR:-output}/$url_path/index.html"

            # Perform the rebuild check here
            common_rebuild_check "$output_html_file"
            local common_result=$?
            local needs_rebuild=false

            if [ $common_result -eq 0 ]; then
                needs_rebuild=true # Common checks failed (config changed, template newer, output missing)
            else # common_result is 2 (output exists and newer than templates/locale)
                local input_time=$(get_file_mtime "$file")
                local output_time=$(get_file_mtime "$output_html_file")
                if (( input_time > output_time )); then
                    needs_rebuild=true # Input file is newer
                fi
            fi

            # Check if this post needs rebuilding due to related posts cache invalidation
            if ! $ram_mode_active && [ "$needs_rebuild" = false ] && [ -n "${RELATED_POSTS_INVALIDATED_LIST:-}" ] && [ -f "$RELATED_POSTS_INVALIDATED_LIST" ]; then
                if grep -Fxq "$slug" "$RELATED_POSTS_INVALIDATED_LIST" 2>/dev/null; then
                    needs_rebuild=true # Related posts cache was invalidated
                    echo -e "Rebuilding ${GREEN}$(basename "$file")${NC} due to related posts cache invalidation"
                fi
            fi

            if $needs_rebuild; then
                files_to_process_list+=("$line")
                files_to_process_count=$((files_to_process_count + 1))
            else
                # Only print skip message if not rebuilding
                echo -e "Skipping unchanged file: ${YELLOW}$(basename "$file")${NC}"
                skipped_count=$((skipped_count + 1))
            fi
        done < <(
            if $ram_mode_active; then
                printf '%s\n' "$file_index_data" | awk 'NF'
            else
                cat "$file_index"
            fi
        )
    fi

    # Check if any files need processing
    if [ $files_to_process_count -eq 0 ]; then
        echo -e "${GREEN}All $total_file_count posts are up to date.${NC}"
        echo -e "${GREEN}Markdown posts processing complete!${NC}"
        return 0
    fi

    echo -e "Found ${GREEN}$files_to_process_count${NC} posts needing processing out of $total_file_count (Skipped: $skipped_count)."

    if $ram_mode_active && [ "${ENABLE_RELATED_POSTS:-true}" = true ]; then
        prepare_related_posts_ram_cache "${RELATED_POSTS_COUNT:-3}"
    fi

    # Define a function for processing a single file line from the *filtered* list
    process_single_file_for_rebuild() {
        local line="$1"

        # Read the line from the argument variable
        local file filename title date lastmod tags slug image image_caption description author_name author_email
        IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email <<< "$line"

        # No need for the basic check here, already done in pre-filter

        # Create output path based on slug format (copied logic)
        local output_path
        local year month day
        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
            year="${BASH_REMATCH[1]}"
            month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
            day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
        else
            year=$(date +%Y); month=$(date +%m); day=$(date +%d)
        fi
        local url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
        url_path="${url_path//Year/$year}"; url_path="${url_path//Month/$month}";
        url_path="${url_path//Day/$day}"; url_path="${url_path//slug/$slug}"
        output_path="${OUTPUT_DIR:-output}/$url_path"

        # Call the conversion function, skipping internal rebuild checks because this
        # function only receives files pre-selected for rebuild.
        if ! convert_markdown "$file" "$output_path" "$title" "$date" "$lastmod" "$tags" "$slug" "$image" "$image_caption" "$description" "$author_name" "$author_email" true; then
            local exit_code=$?
            echo -e "${RED}ERROR:${NC} convert_markdown failed for '$file' with exit code $exit_code. Output HTML may be missing or incomplete." >&2
        fi
    }

    # Use GNU parallel if available
    if $ram_mode_active; then
        local cores
        cores=$(get_parallel_jobs)
        if [ "$cores" -gt "$files_to_process_count" ]; then
            cores="$files_to_process_count"
        fi

        if [ "$files_to_process_count" -gt 1 ] && [ "$cores" -gt 1 ]; then
            echo -e "${YELLOW}Using shell parallel workers for $files_to_process_count RAM-mode posts${NC}"

            local worker_pids=()
            local worker_idx
            for ((worker_idx = 0; worker_idx < cores; worker_idx++)); do
                (
                    local idx
                    for ((idx = worker_idx; idx < files_to_process_count; idx += cores)); do
                        process_single_file_for_rebuild "${files_to_process_list[$idx]}"
                    done
                ) &
                worker_pids+=("$!")
            done

            local pid
            local worker_failed=false
            for pid in "${worker_pids[@]}"; do
                if ! wait "$pid"; then
                    worker_failed=true
                fi
            done
            if $worker_failed; then
                echo -e "${RED}Parallel RAM-mode post processing failed.${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Using sequential processing for $files_to_process_count RAM-mode posts${NC}"
            local line
            for line in "${files_to_process_list[@]}"; do
                process_single_file_for_rebuild "$line"
            done
        fi
    elif [ "${HAS_PARALLEL:-false}" = true ]; then
        echo -e "${GREEN}Using GNU parallel to process $files_to_process_count posts${NC}"
        local cores
        cores=$(get_parallel_jobs)

        # Export functions and variables needed by parallel tasks
        # Note: We export the new process function
        export -f convert_markdown process_single_file_for_rebuild
        # Export dependencies of convert_markdown and its helpers
        export -f file_needs_rebuild get_file_mtime common_rebuild_check config_has_changed # Still needed by convert_markdown *internally* for now
        export -f calculate_reading_time generate_slug format_date fix_url parse_metadata extract_metadata convert_markdown_to_html
        export -f format_iso8601_post_date
        export -f portable_md5sum # Used by cache funcs
        export CACHE_DIR FORCE_REBUILD OUTPUT_DIR SITE_URL URL_SLUG_FORMAT HEADER_TEMPLATE FOOTER_TEMPLATE
        export SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME MARKDOWN_PROCESSOR MARKDOWN_PL_PATH DATE_FORMAT TIMEZONE SHOW_TIMEZONE
        export MSG_PUBLISHED_ON MSG_UPDATED_ON MSG_READING_TIME_TEMPLATE # Export needed locale messages
        export CONFIG_HASH_FILE BSSG_CONFIG_CHANGED_STATUS # Export status for common_rebuild_check
        export ENABLE_RELATED_POSTS RELATED_POSTS_COUNT # Export related posts configuration

        # Process filtered lines in parallel
        printf "%s\n" "${files_to_process_list[@]}" | parallel --jobs "$cores" --will-cite process_single_file_for_rebuild {} || { echo -e "${RED}Parallel post processing failed.${NC}"; exit 1; }
    else
        # Sequential processing for filtered list
        echo -e "${YELLOW}Using sequential processing for $files_to_process_count posts${NC}"
        local line
        for line in "${files_to_process_list[@]}"; do
            process_single_file_for_rebuild "$line"
        done
    fi

    echo -e "${GREEN}Markdown posts processing complete!${NC}"
}

# --- Post Generation Functions --- END ---

# Make the main function available for sourcing
export -f process_all_markdown_files convert_markdown # Export the main function and conversion
# Export helpers needed if sourced externally? Maybe not. 
