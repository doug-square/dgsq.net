#!/usr/bin/env bash
#
# BSSG - Post Generation
# Functions for converting markdown posts to HTML.
#

# Ensure necessary color variables are available if sourced independently
# RED='${RED:-\\033[0;31m}' # Removed - Should be inherited from main export
# GREEN='${GREEN:-\\033[0;32m}' # Removed - Should be inherited from main export
# YELLOW='${YELLOW:-\\033[0;33m}' # Removed - Should be inherited from main export
# NC='${NC:-\\033[0m}' # Removed - Should be inherited from main export

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_posts.sh"; exit 1; }
# shellcheck source=content.sh disable=SC1091
source "$(dirname "$0")/content.sh" || { echo >&2 "Error: Failed to source content.sh from generate_posts.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_posts.sh"; exit 1; } # For file_needs_rebuild checks etc.

# --- Post Generation Functions --- START ---

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
    
    local content_cache_file="${CACHE_DIR:-.bssg_cache}/content/$(basename "$input_file")"
    local output_html_file="$output_base_path/index.html"

    # Check if the source file exists
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}Error: Source file '$input_file' not found${NC}" >&2
        return 1
    fi

    # Skip if output file is newer than input file and no force rebuild
    if ! file_needs_rebuild "$input_file" "$output_html_file"; then
        echo -e "Skipping unchanged file: ${YELLOW}$(basename "$input_file")${NC}"
        return 0
    fi

    echo -e "Processing post: ${GREEN}$(basename "$input_file")${NC}"

    # Try to get content from cache or file
    local content=""
    if [ "${FORCE_REBUILD:-false}" = false ] && [ -f "$content_cache_file" ] && [ "$content_cache_file" -nt "$input_file" ]; then
        content=$(cat "$content_cache_file")
    else
        # Extract content from source file
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
                        continue # Skip the closing --- line itself
                    fi
                fi
                if ! $in_frontmatter && $found_frontmatter; then
                    content+="$line"$'\n'
                fi
            done
        } < "$input_file"
        
        # If no frontmatter was found, use the whole file as content
        if ! $found_frontmatter; then
            content=$(cat "$input_file")
        fi
        
        # Cache the content
        mkdir -p "$(dirname "$content_cache_file")"
        printf '%s' "$content" > "$content_cache_file"
    fi

    # Calculate reading time
    local reading_time
    reading_time=$(calculate_reading_time "$content")

    # Convert markdown content to HTML
    local html_content
    if [[ "$input_file" == *.html ]]; then
        # For HTML files, extract content between <body> tags (simple approach)
        # Assumes content is already HTML
        html_content=$(sed -n '/<body.*>/,/<\/body>/p' "$input_file" | sed '1d;$d')
        echo -e "Extracted body content from HTML file: ${GREEN}$(basename "$input_file")${NC}"
    elif [[ "$input_file" == *.md ]]; then
        # Original Markdown conversion
        html_content=$(convert_markdown_to_html "$content")
        if [ $? -ne 0 ]; then
            echo -e "${RED}Markdown conversion failed for '$input_file', skipping html generation.${NC}" >&2
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
                tags_html+=$(printf ' <a href="%s/tags/%s/" class="tag">%s</a>' "${SITE_URL:-}" "$tag_slug" "$tag")
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

        # Function to format date to ISO 8601 with corrected timezone
        format_iso8601() {
            local input_dt="$1"
            local iso_dt=""
            if [ -z "$input_dt" ]; then echo ""; return; fi

            # Handle "now" separately
            if [ "$input_dt" = "now" ]; then
                iso_dt=$(LC_ALL=C date +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
            else
                # Try parsing different formats based on OS
                # Add LC_ALL=C for consistent parsing
                if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
                    # macOS/BSD: Try formats one by one with date -j -f
                    # Format 1: YYYY-MM-DD HH:MM:SS ZZZZ (e.g., +0200)
                    iso_dt=$(LC_ALL=C date -j -f "%Y-%m-%d %H:%M:%S %z" "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
                    # Format 2: YYYY-MM-DD HH:MM:SS
                    [ -z "$iso_dt" ] && iso_dt=$(LC_ALL=C date -j -f "%Y-%m-%d %H:%M:%S" "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
                    # Format 3: YYYY-MM-DD (assume T00:00:00)
                    [ -z "$iso_dt" ] && iso_dt=$(LC_ALL=C date -j -f "%Y-%m-%d" "$input_dt" +"%Y-%m-%dT00:00:00%z" 2>/dev/null)
                    # Format 4: RFC 2822 subset (e.g., 07 Sep 2023 08:10:00 +0200)
                    [ -z "$iso_dt" ] && iso_dt=$(LC_ALL=C date -j -f "%d %b %Y %H:%M:%S %z" "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
                else # Linux
                    # GNU date -d is more flexible and handles many formats automatically
                    iso_dt=$(LC_ALL=C date -d "$input_dt" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null)
                fi
            fi

            # If parsing succeeded, fix timezone format
            if [ -n "$iso_dt" ]; then
                 # Fix timezone format from +0000 to +00:00 or Z
                 if [[ "$iso_dt" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
                     local tz_offset="${BASH_REMATCH[0]}"
                     local tz_hh="${BASH_REMATCH[1]}"
                     local tz_mm="${BASH_REMATCH[2]}"
                     if [ "$tz_hh" == "+00" ] && [ "$tz_mm" == "00" ]; then
                         iso_dt="${iso_dt%$tz_offset}Z"
                     else
                         iso_dt="${iso_dt%$tz_offset}${tz_hh}:${tz_mm}"
                     fi
                 fi
                 echo "$iso_dt"
            else
                echo "" # Return empty if formatting failed
            fi
        }

        iso_date=$(format_iso8601 "$date")
        # Use date as fallback for lastmod, then format
        iso_lastmod_date=$(format_iso8601 "${lastmod:-$date}")
        # If lastmod still empty, use iso_date as fallback
        [ -z "$iso_lastmod_date" ] && iso_lastmod_date="$iso_date"

        # Fallback to build time if both are empty (should be rare)
        if [ -z "$iso_date" ]; then
            local now_iso=$(format_iso8601 "now")
            iso_date="$now_iso"
            iso_lastmod_date="$now_iso"
        fi

        local image_url=""
        if [ -n "$image" ]; then
             image_url=$(fix_url "$image")
        fi

        # Create JSON-LD
        schema_json_ld=$(printf '<script type="application/ld+json">\n{\n  "@context": "https://schema.org",\n  "@type": "Article",\n  "headline": "%s",\n  "datePublished": "%s",\n  "dateModified": "%s",\n  "author": {\n    "@type": "Person",\n    "name": "%s",\n    "email": "%s"\n  },\n  "publisher": {\n    "@type": "Organization",\n    "name": "%s",\n    "logo": {\n      "@type": "ImageObject",\n      "url": "%s/logo.png"\n    }\n  },\n  "description": "%s",\n  "mainEntityOfPage": {\n    "@type": "WebPage",\n    "@id": "%s%s"\n  }%s\n}\n</script>' \
          "$(echo "$title" | sed 's/"/\"/g')" \
          "$iso_date" \
          "$iso_lastmod_date" \
          "${AUTHOR_NAME:-Anonymous}" \
          "${AUTHOR_EMAIL:-anonymous@example.com}" \
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
    local post_meta="<div class=\"page-meta\">${MSG_PUBLISHED_ON:-Published on}: $formatted_date"
    if [ "$formatted_date" != "$formatted_lastmod" ]; then
        post_meta+=" &bull; ${MSG_UPDATED_ON:-Updated on}: $formatted_lastmod"
    fi
    post_meta+=" &bull; $post_meta_reading_time</div>"
    
    # Construct featured image HTML
    local image_html=""
    if [ -n "$image" ]; then
        local alt_text="${image_caption:-$title}"
        image_html="<div class=\"featured-image\"><img src=\"$(fix_url "$image")\" alt=\"$alt_text\"><div class=\"image-caption\">${image_caption:-$title}</div></div>"
    fi
    
    # Construct article body
    local final_html="${header_content}"
    final_html+=$(printf '<article class="post">\n  <h1>%s</h1>\n%s\n%s\n%s\n%s\n</article>\n' "$title" "$post_meta" "$image_html" "$html_content" "$tags_html")

    # Replace placeholders in footer content
    local current_year=$(date +'%Y')
    footer_content=${footer_content//\{\{current_year\}\}/$current_year}
    footer_content=${footer_content//\{\{author_name\}\}/${AUTHOR_NAME:-Anonymous}}

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

    if [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index not found at '$file_index'. Run indexing first.${NC}" >&2
        return 1
    fi

    local total_file_count=$(wc -l < "$file_index")
    if [ "$total_file_count" -eq 0 ]; then
        echo -e "${YELLOW}No posts found in file index. Skipping post generation.${NC}"
        return 0
    fi
    echo -e "Checking ${GREEN}$total_file_count${NC} potential posts listed in index."

    # Pre-filter files that need rebuilding
    local files_to_process_list=()
    local files_to_process_count=0
    local skipped_count=0

    # Get template/locale mtimes once (requires utils.sh and cache.sh to be sourced)
    # IMPORTANT: Assumes get_file_mtime, TEMPLATES_DIR, THEME, LOCALE_DIR, SITE_LANG are available
    local template_dir="${TEMPLATES_DIR:-templates}"
    if [ -d "$template_dir/${THEME:-default}" ]; then
        template_dir="$template_dir/${THEME:-default}"
    fi
    local header_template="$template_dir/header.html"
    local footer_template="$template_dir/footer.html"
    local active_locale_file=""
    if [ -f "${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh" ]; then
        active_locale_file="${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh"
    elif [ -f "${LOCALE_DIR:-locales}/en.sh" ]; then
        active_locale_file="${LOCALE_DIR:-locales}/en.sh"
    fi
    local header_time=$(get_file_mtime "$header_template")
    local footer_time=$(get_file_mtime "$footer_template")
    local locale_time=$(get_file_mtime "$active_locale_file")

    while IFS= read -r line; do
        local file filename title date lastmod tags slug image image_caption description
        IFS='|' read -r file filename title date lastmod tags slug image image_caption description <<< "$line"

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
        # IMPORTANT: Requires common_rebuild_check, get_file_mtime to be available
        #            Requires BSSG_CONFIG_CHANGED_STATUS to be exported by main.sh
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

        if $needs_rebuild; then
            files_to_process_list+=("$line")
            files_to_process_count=$((files_to_process_count + 1))
        else
            # Only print skip message if not rebuilding
            echo -e "Skipping unchanged file: ${YELLOW}$(basename "$file")${NC}"
            skipped_count=$((skipped_count + 1))
        fi
    done < "$file_index"

    # Check if any files need processing
    if [ $files_to_process_count -eq 0 ]; then
        echo -e "${GREEN}All $total_file_count posts are up to date.${NC}"
        echo -e "${GREEN}Markdown posts processing complete!${NC}"
        return 0
    fi

    echo -e "Found ${GREEN}$files_to_process_count${NC} posts needing processing out of $total_file_count (Skipped: $skipped_count)."

    # Define a function for processing a single file line from the *filtered* list
    # Note: This function now assumes the file *needs* processing.
    process_single_file_for_rebuild() {
        local line="$1"

        # Read the line from the argument variable
        local file filename title date lastmod tags slug image image_caption description
        IFS='|' read -r file filename title date lastmod tags slug image image_caption description <<< "$line"

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

        # Call the main conversion function
        # We no longer rely on its internal file_needs_rebuild check
        # TODO: Consider modifying convert_markdown to accept a force flag or skip its check
        if ! convert_markdown "$file" "$output_path" "$title" "$date" "$lastmod" "$tags" "$slug" "$image" "$image_caption" "$description"; then
            local exit_code=$?
            echo -e "${RED}ERROR:${NC} convert_markdown failed for '$file' with exit code $exit_code. Output HTML may be missing or incomplete." >&2
        fi
    }

    # Use GNU parallel if available
    if [ "${HAS_PARALLEL:-false}" = true ]; then
        echo -e "${GREEN}Using GNU parallel to process $files_to_process_count posts${NC}"
        local cores=1
        if command -v nproc > /dev/null 2>&1; then cores=$(nproc);
        elif command -v sysctl > /dev/null 2>&1; then cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1); fi

        # Export functions and variables needed by parallel tasks
        # Note: We export the new process function
        export -f convert_markdown process_single_file_for_rebuild
        # Export dependencies of convert_markdown and its helpers
        export -f file_needs_rebuild get_file_mtime common_rebuild_check config_has_changed # Still needed by convert_markdown *internally* for now
        export -f calculate_reading_time generate_slug format_date fix_url parse_metadata extract_metadata convert_markdown_to_html
        export -f portable_md5sum # Used by cache funcs
        export CACHE_DIR FORCE_REBUILD OUTPUT_DIR SITE_URL URL_SLUG_FORMAT HEADER_TEMPLATE FOOTER_TEMPLATE
        export SITE_TITLE SITE_DESCRIPTION AUTHOR_NAME MARKDOWN_PROCESSOR MARKDOWN_PL_PATH DATE_FORMAT TIMEZONE SHOW_TIMEZONE
        export MSG_PUBLISHED_ON MSG_UPDATED_ON MSG_READING_TIME_TEMPLATE # Export needed locale messages
        export CONFIG_HASH_FILE BSSG_CONFIG_CHANGED_STATUS # Export status for common_rebuild_check

        # Process filtered lines in parallel
        printf "%s\n" "${files_to_process_list[@]}" | parallel --jobs "$cores" process_single_file_for_rebuild {} || { echo -e "${RED}Parallel post processing failed.${NC}"; exit 1; }
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