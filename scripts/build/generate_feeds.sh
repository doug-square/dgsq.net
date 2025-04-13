#!/usr/bin/env bash
#
# BSSG - Feed Generation
# Handles the creation of sitemap.xml and rss.xml.
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from generate_feeds.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from generate_feeds.sh"; exit 1; }
# Source content.sh to get convert_markdown_to_html
# shellcheck source=content.sh disable=SC1091
source "$(dirname "$0")/content.sh" || { echo >&2 "Error: Failed to source content.sh from generate_feeds.sh"; exit 1; }
# Note: Needs access to primary_pages and SECONDARY_PAGES which should be exported by templates.sh

# Function to get the latest lastmod date from a file index, optionally filtered
# Usage: get_latest_mod_date <index_file> [field_index] [filter_pattern] [date_format]
# Example: get_latest_mod_date "$file_index" 5 "" "%Y-%m-%d" # Latest overall post
# Example: get_latest_mod_date "$tags_index" 5 "^tag-slug|" "%Y-%m-%d" # Latest for a tag
get_latest_mod_date() {
    local index_file="$1"
    local date_field_index="${2:-5}" # Default to 5 for lastmod in file_index/tags_index
    local filter_pattern="$3"       # Optional grep pattern
    local date_format="${4:-%Y-%m-%d}" # Default sitemap format

    if [ ! -f "$index_file" ]; then
        echo "$(format_date "now" "$date_format")" # Fallback to now if index missing
        return
    fi

    local latest_date_str
    if [ -n "$filter_pattern" ]; then
        # Filter, extract date, sort numerically (YYYY-MM-DD is sortable), get latest
        latest_date_str=$(grep -E "$filter_pattern" "$index_file" | cut -d'|' -f"$date_field_index" | sort -r | head -n 1)
    else
        # Extract date, sort numerically, get latest
        latest_date_str=$(cut -d'|' -f"$date_field_index" "$index_file" | sort -r | head -n 1)
    fi

    if [ -n "$latest_date_str" ]; then
        # Attempt to format the found date string
        local formatted_date=$(format_date "$latest_date_str" "$date_format")
        if [ -n "$formatted_date" ]; then
             echo "$formatted_date"
        else
             # Fallback if format_date fails (e.g., invalid date string)
             echo "$(format_date "now" "$date_format")"
        fi
    else
        # Fallback if no matching entries or dates found
        echo "$(format_date "now" "$date_format")"
    fi
}

# Generate sitemap.xml
generate_sitemap() {
    echo -e "${YELLOW}Generating sitemap.xml...${NC}"

    local sitemap="$OUTPUT_DIR/sitemap.xml"
    local file_index="$CACHE_DIR/file_index.txt"
    local tags_index="$CACHE_DIR/tags_index.txt"
    local primary_pages_cache="$CACHE_DIR/primary_pages.tmp"
    local secondary_pages_cache="$CACHE_DIR/secondary_pages.tmp"
    local config_hash_file="$CONFIG_HASH_FILE" # Use the global var
    local script_path="$BSSG_SCRIPT_DIR/build/generate_feeds.sh" # Path to this script
    local sitemap_date_fmt="%Y-%m-%d"

    # Determine active locale file
    local active_locale_file=""
    if [ -f "${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh" ]; then
        active_locale_file="${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh"
    elif [ -f "${LOCALE_DIR:-locales}/en.sh" ]; then # Fallback to en
        active_locale_file="${LOCALE_DIR:-locales}/en.sh"
    fi

    # Check if sitemap needs rebuild (Specific check)
    if [ -f "$sitemap" ]; then
        local sitemap_mtime=$(get_file_mtime "$sitemap")
        local rebuild_needed=false

        # List of dependencies to check
        local dependencies=("$file_index" "$tags_index" "$primary_pages_cache" "$secondary_pages_cache" "$config_hash_file" "$script_path")
        if [ -n "$active_locale_file" ]; then
             dependencies+=("$active_locale_file")
        fi

        # Check FORCE_REBUILD flag
        if [ "${FORCE_REBUILD:-false}" = true ]; then
            rebuild_needed=true
        else
            # Check modification times of dependencies
            for dep in "${dependencies[@]}"; do
                if [ -e "$dep" ] && [[ $(get_file_mtime "$dep") -gt $sitemap_mtime ]]; then
                    # echo "DEBUG: Sitemap rebuild triggered by newer dependency: $dep" >&2 # Optional debug
                    rebuild_needed=true
                    break
                fi
            done
        fi

        # If no rebuild needed based on mtimes, skip
        if [ "$rebuild_needed" = false ]; then
            echo -e "${GREEN}Sitemap is up to date (based on specific dependencies), skipping...${NC}"
            return 0
        fi
    # else
    #     echo "DEBUG: Sitemap file missing, forcing generation." >&2 # Optional debug
    fi


    # --- Pre-calculate latest dates ---
    # Latest post overall (using lastmod field - index 5)
    local latest_post_mod_date=$(get_latest_mod_date "$file_index" 5 "" "$sitemap_date_fmt")
    # Latest static page (using date field - index 3)
    local latest_static_page_date=$(get_latest_mod_date "$secondary_pages_cache" 3 "" "$sitemap_date_fmt")


    # Create the sitemap header
    cat > "$sitemap" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
EOF

    # --- Add Homepage ---
    # Use the overall latest post mod date
    cat >> "$sitemap" << EOF
    <url>
        <loc>$(fix_url "/")</loc>
        <lastmod>${latest_post_mod_date}</lastmod>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
    </url>
EOF

    # --- Add Posts (from file index) ---
    if [ -f "$file_index" ]; then
        # Correctly read all fields including lastmod, tags, and the actual slug
        while IFS='|' read -r file filename title date lastmod tags slug image image_caption description || [[ -n "$file" ]]; do
            # Skip if essential fields are missing
            if [ -z "$file" ] || [ -z "$date" ] || [ -z "$lastmod" ] || [ -z "$slug" ]; then
                continue
            fi
            # Apply URL_SLUG_FORMAT for the URL
            local year month day
            # Use original date for URL generation structure
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                # Skip if date format unrecognized
                continue
            fi
            local formatted_path="${URL_SLUG_FORMAT//Year/$year}"
            formatted_path="${formatted_path//Month/$month}"
            formatted_path="${formatted_path//Day/$day}"
            formatted_path="${formatted_path//slug/$slug}"
            # Create clean URL
            local item_url="/$(echo "$formatted_path" | sed 's|/*$|/|')"
            # Use the lastmod field
            local mod_time=$(format_date "$lastmod" "$sitemap_date_fmt")
            # Fallback if formatting failed
            [ -z "$mod_time" ] && mod_time=$(format_date "now" "$sitemap_date_fmt")
            cat >> "$sitemap" << EOF
    <url>
        <loc>$(fix_url "$item_url")</loc>
        <lastmod>${mod_time}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
EOF
        done < "$file_index"
    fi

    # --- Add Primary Pages (from cache file) ---
    if [ -f "$primary_pages_cache" ]; then
        echo -e "Adding $(wc -l < "$primary_pages_cache" | tr -d ' ') primary pages to sitemap..."
        while IFS='|' read -r _ url date source_file || [[ -n "$url" ]]; do
            # Create clean URL
            local sitemap_url
            sitemap_url=$(echo "$url" | sed 's|/index.html$|/|; s|/*$|/|')
            # Use the date from the frontmatter/meta
            local mod_time=$(format_date "$date" "$sitemap_date_fmt")
            # Fallback if formatting failed
            [ -z "$mod_time" ] && mod_time=$(format_date "now" "$sitemap_date_fmt")
            cat >> "$sitemap" << EOF
    <url>
        <loc>${sitemap_url}</loc>
        <lastmod>${mod_time}</lastmod>
        <changefreq>monthly</changefreq>
        <priority>0.7</priority>
    </url>
EOF
        done < "$primary_pages_cache"
    fi

    # --- Add Secondary Pages (from cache file) ---
    if [ -f "$secondary_pages_cache" ]; then
         local secondary_page_count=$(wc -l < "$secondary_pages_cache")
         if [ "$secondary_page_count" -gt 0 ]; then
             echo -e "Adding $secondary_page_count secondary pages to sitemap..."
             while IFS='|' read -r _ url date source_file || [[ -n "$url" ]]; do
                 if [ -z "$url" ]; then continue; fi
                 local mod_time=$(format_date "$date" "$sitemap_date_fmt")
                 # Fallback if formatting failed
                 [ -z "$mod_time" ] && mod_time=$(format_date "now" "$sitemap_date_fmt")
                 # Ensure trailing slash if it looks like a directory page
                 if [[ "$url" == */index.html ]]; then
                     url=$(echo "$url" | sed 's|/index.html$|/|')
                 elif [[ "$url" != *.html && "$url" != */ ]]; then
                     url="${url}/"
                 fi
                 cat >> "$sitemap" << EOF
    <url>
        <loc>${url}</loc>
        <lastmod>${mod_time}</lastmod>
        <changefreq>monthly</changefreq>
        <priority>0.6</priority>
    </url>
EOF
             done < "$secondary_pages_cache"
         fi
    fi

    # --- Add Tag Index Page ---
    local tag_index_file="$OUTPUT_DIR/tags/index.html"
    if [ -f "$tag_index_file" ]; then
        # Use the overall latest post mod date
        cat >> "$sitemap" << EOF
    <url>
        <loc>$(fix_url "/tags/")</loc>
        <lastmod>${latest_post_mod_date}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.5</priority>
    </url>
EOF
    fi

    # --- Add Archive Index Page ---
    local archive_index_file="$OUTPUT_DIR/archives/index.html"
    if [ -f "$archive_index_file" ] && [ "${ENABLE_ARCHIVES:-false}" = true ]; then
        # Use the overall latest post mod date
        cat >> "$sitemap" << EOF
    <url>
        <loc>$(fix_url "/archives/")</loc>
        <lastmod>${latest_post_mod_date}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.5</priority>
    </url>
EOF
    fi

    # --- Add Individual Tag Pages ---
    # We need tags_index.txt for accurate dates
    if [ -f "$tags_index" ]; then
        # Find index.html files within first-level subdirectories of $OUTPUT_DIR/tags
        find "$OUTPUT_DIR/tags/"* -maxdepth 0 -type d -print0 | while IFS= read -r -d $'\0' tag_dir; do
            local page_file="$tag_dir/index.html"
            if [ ! -f "$page_file" ]; then continue; fi

            local tag_slug clean_url mod_time
            tag_slug=$(basename "$tag_dir")
            # Use the tag slug to find the latest post date for this tag from tags_index (Field 5: PostLastMod)
            mod_time=$(get_latest_mod_date "$tags_index" 5 "^[^|]+\\|${tag_slug}\\|" "$sitemap_date_fmt")
            clean_url="/tags/${tag_slug}/" # Trailing slash structure

            cat >> "$sitemap" << EOF
    <url>
        <loc>$(fix_url "$clean_url")</loc>
        <lastmod>${mod_time}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.4</priority>
    </url>
EOF
        done
    else
         echo -e "${YELLOW}Warning: Tags index '$tags_index' not found. Cannot determine accurate lastmod for individual tag pages.${NC}"
         # Optionally fall back to file mtime? Or skip? Skipping for now.
    fi


    # --- Add Individual Archive Pages ---
    if [ "${ENABLE_ARCHIVES:-false}" = true ] && [ -f "$file_index" ]; then
        # Find directories like /archives/YYYY, /archives/YYYY/MM, /archives/YYYY/MM/DD
        find "$OUTPUT_DIR/archives/"* -type d -print0 | while IFS= read -r -d $'\0' dir_path; do
            local page_file="$dir_path/index.html"
            if [ -f "$page_file" ]; then
                local clean_url_base clean_url mod_time date_pattern
                clean_url_base="${dir_path#$OUTPUT_DIR}" # e.g., /archives/2023 or /archives/2023/01
                clean_url="${clean_url_base}/" # Add trailing slash

                # Determine date pattern for filtering file_index based on directory structure
                date_pattern=$(echo "$clean_url_base" | sed -n 's|^/archives/\([0-9]\{4\}\)$|^\1-|p; s|^/archives/\([0-9]\{4\}\)/\([0-9]\{2\}\)$|^\1-\2-|p; s|^/archives/\([0-9]\{4\}\)/\([0-9]\{2\}\)/\([0-9]\{2\}\)$|^\1-\2-\3|p')

                if [ -n "$date_pattern" ]; then
                     # Get latest post in this period using lastmod (field 5) by filtering on date (field 4) in file_index
                     # The grep pattern needs to match the date field (4th field)
                     local grep_pattern="^[^|]+\\|[^|]+\\|[^|]+\\|${date_pattern}"
                     mod_time=$(get_latest_mod_date "$file_index" 5 "$grep_pattern" "$sitemap_date_fmt")
                else
                     # Fallback if pattern extraction failed (e.g., /archives/ itself, though handled separately)
                     mod_time=$(format_date_from_timestamp "$(get_file_mtime "$page_file")" "$sitemap_date_fmt")
                fi

                cat >> "$sitemap" << EOF
    <url>
        <loc>$(fix_url "$clean_url")</loc>
        <lastmod>${mod_time}</lastmod>
        <changefreq>monthly</changefreq>
        <priority>0.5</priority>
    </url>
EOF
            fi
        done
    elif [ "${ENABLE_ARCHIVES:-false}" = true ]; then
         echo -e "${YELLOW}Warning: File index '$file_index' not found. Cannot determine accurate lastmod for individual archive pages.${NC}"
    fi


    # --- Add pages.html (Secondary Pages Index) ---
    local pages_html_file="$OUTPUT_DIR/pages.html"
    if [ -f "$pages_html_file" ]; then
        # Use the pre-calculated latest static page date
        cat >> "$sitemap" << EOF
    <url>
        <loc>$(fix_url "/pages.html")</loc> <!-- Assuming this page doesn't get a trailing slash -->
        <lastmod>${latest_static_page_date}</lastmod>
        <changefreq>monthly</changefreq>
        <priority>0.6</priority>
    </url>
EOF
    fi

    # --- Close sitemap ---
    echo "</urlset>" >> "$sitemap"
    echo -e "${GREEN}Sitemap generated!${NC}"
}

# Generate RSS feed
generate_rss() {
    echo -e "${YELLOW}Generating RSS feed...${NC}"

    # Ensure needed functions/vars are available (especially if run standalone/debug)
    # convert_markdown_to_html should be sourced from content.sh
    # MD5_CMD should be exported by deps.sh
    # CACHE_DIR, MARKDOWN_PROCESSOR, MARKDOWN_PL_PATH etc should be exported by config_loader.sh
    if ! command -v convert_markdown_to_html &> /dev/null; then
        echo -e "${RED}Error: convert_markdown_to_html function not found. Make sure content.sh was sourced.${NC}" >&2
        return 1
    fi
    if [ -z "${MD5_CMD:-}" ]; then
        echo -e "${RED}Error: MD5_CMD is not set. Make sure deps.sh was sourced and exported it.${NC}" >&2
        return 1
    fi
    if [ -z "${CACHE_DIR:-}" ]; then
        echo -e "${RED}Error: CACHE_DIR is not set.${NC}" >&2
        return 1
    fi

    local rss="$OUTPUT_DIR/rss.xml"
    local file_index="$CACHE_DIR/file_index.txt"

    # Check if RSS feed needs to be rebuilt
    if ! file_needs_rebuild "$file_index" "$rss"; then
        echo -e "${GREEN}RSS feed is up to date, skipping...${NC}"
        return 0
    fi

    local rss_date_fmt="%a, %d %b %Y %H:%M:%S %z"
    local now=$(format_date "now" "$rss_date_fmt")

    # Get build timestamp in ISO 8601 for atom:updated fallback
    local build_timestamp_iso=$(format_date "now" "%Y-%m-%dT%H:%M:%S%z")
    # Convert RFC-2822 timezone (+0000) to ISO 8601 (+00:00) if needed
    # Bash doesn't support %:z, use date command again if necessary
    if [[ "$build_timestamp_iso" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
        build_timestamp_iso="${build_timestamp_iso::${#build_timestamp_iso}-2}:${BASH_REMATCH[2]}"
    fi

    # Create the RSS feed
    cat > "$rss" << EOF
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
    <title>${MSG_RSS_FEED_TITLE:-${SITE_TITLE} - RSS Feed}</title>
    <link>${SITE_URL}</link>
    <description>${MSG_RSS_FEED_DESCRIPTION:-${SITE_DESCRIPTION}}</description>
    <language>${SITE_LANG:-en}</language>
    <lastBuildDate>$(format_date "now" "%a, %d %b %Y %H:%M:%S %z")</lastBuildDate>
    <atom:link href="$(fix_url "/rss.xml")" rel="self" type="application/rss+xml" />
EOF

    # Use the dedicated RSS item limit variable, default to 15
    local rss_item_limit=${RSS_ITEM_LIMIT:-15}

    # Read file_index.txt, sort by original date (field 4), take top N
    sort -t'|' -k4,4r "$file_index" | head -n "$rss_item_limit" | while IFS='|' read -r file filename title date lastmod tags slug image image_caption description; do
        # Skip if essential fields are missing
        if [ -z "$file" ] || [ -z "$title" ] || [ -z "$date" ] || [ -z "$lastmod" ] || [ -z "$slug" ]; then
            echo "Warning: Skipping RSS item due to missing fields for file: $file" >&2
            continue
        fi

        # Format dates for RSS
        local pub_date=$(format_date "$date" "$rss_date_fmt")
        # Updated date for <atom:updated> needs ISO 8601 format
        local updated_date_iso=$(format_date "$lastmod" "%Y-%m-%dT%H:%M:%S%z")
        # Convert timezone format again if needed
        if [[ "$updated_date_iso" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
             updated_date_iso="${updated_date_iso::${#updated_date_iso}-2}:${BASH_REMATCH[2]}"
        fi
        # Fallback for updated_date_iso
        [ -z "$updated_date_iso" ] && updated_date_iso="$build_timestamp_iso"

        # Construct post URL based on URL_SLUG_FORMAT
        local year month day formatted_path item_url
        if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
            year="${BASH_REMATCH[1]}"
            month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
            day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
        else
             echo "Warning: Invalid date format '$date' for file $file, cannot generate URL." >&2
             continue # Skip item if URL cannot be generated
        fi
        formatted_path="${URL_SLUG_FORMAT//Year/$year}"
        formatted_path="${formatted_path//Month/$month}"
        formatted_path="${formatted_path//Day/$day}"
        formatted_path="${formatted_path//slug/$slug}"
        item_url="/$(echo "$formatted_path" | sed 's|/*$|/|')" # Ensure trailing slash

        local full_url=$(fix_url "$item_url") # Use fix_url to prepend SITE_URL

        # --- RSS Item Description Enhancement ---
        local item_description_content=""

        # Check if full content should be included
        if [ "${RSS_INCLUDE_FULL_CONTENT:-false}" = true ]; then
            # Convert full content from cached raw markdown on the fly
            local raw_content_cache_file="${CACHE_DIR:-.bssg_cache}/content/$(basename "${file}")"
            local raw_content=""
            local converted_html=""

            if [ -f "$raw_content_cache_file" ]; then
                # Read the raw cached content
                raw_content=$(cat "$raw_content_cache_file")
                
                # Convert raw markdown to HTML
                converted_html=$(convert_markdown_to_html "$raw_content")
                local convert_status=$?

                if [ $convert_status -eq 0 ] && [ -n "$converted_html" ]; then
                    item_description_content="$converted_html"
                else
                    echo "Warning: Failed to convert markdown to HTML for RSS item ($file, status: $convert_status). Falling back to excerpt." >&2
                    item_description_content="$description" # Fallback to excerpt on conversion error
                fi
            else
                # Fallback to excerpt if raw content cache not found
                echo "Warning: Cached raw markdown content file '$raw_content_cache_file' not found for RSS item ($file). Falling back to excerpt." >&2
                item_description_content="$description"
            fi
        else
            # Use excerpt (original logic)
            # Add featured image if available
            if [ -n "$image" ]; then
                # Assume image path is relative to site root or absolute
                local img_src
                [[ "$image" =~ ^https?:// ]] && img_src="$image" || img_src=$(fix_url "$image")
                # Basic HTML escaping for alt/title (replace quotes, &, <, >)
                local img_alt=$(echo "$title" | sed -e 's/&/&amp;/g' -e 's/</&lt;/g' -e 's/>/&gt;/g' -e 's/"/&quot;/g' -e "s/'/&apos;/g")
                local img_title=$(echo "$image_caption" | sed -e 's/&/&amp;/g' -e 's/</&lt;/g' -e 's/>/&gt;/g' -e 's/"/&quot;/g' -e "s/'/&apos;/g")
                 # Default alt to title if caption is empty
                 [ -z "$img_title" ] && img_title="$img_alt"

                # Use standard quotes for HTML attributes within CDATA
                item_description_content+="<img src=\"${img_src}\" alt=\"${img_alt}\" title=\"${img_title}\">"
                 if [ -n "$image_caption" ]; then
                      # Use basic escaping for content within HTML tags inside CDATA
                      local escaped_caption=$(echo "$image_caption" | sed -e 's/&/&amp;/g' -e 's/</&lt;/g' -e 's/>/&gt;/g')
                      item_description_content+="<p><em>${escaped_caption}</em></p>"
                 fi
            fi
            # Add description/excerpt (already extracted, may contain HTML)
            # Needs basic XML entity escaping for CDATA safety (although CDATA handles most) - primarily & < > within the text itself.
            # No need to escape quotes or apostrophes here for CDATA
            item_description_content+="$description" # Use original description directly in CDATA
        fi

        # Wrap final description in CDATA
        local final_description="<![CDATA[${item_description_content}]]>"
        # --- End RSS Item Description Enhancement ---

        cat >> "$rss" << EOF
    <item>
        <title>${title}</title>
        <link>${full_url}</link>
        <guid isPermaLink="true">${full_url}</guid>
        <pubDate>${pub_date}</pubDate>
        <atom:updated>${updated_date_iso}</atom:updated>
        <description>${final_description}</description>
    </item>
EOF
    done

    # Close channel and rss tags
    cat >> "$rss" << EOF
</channel>
</rss>
EOF

    echo -e "${GREEN}RSS feed generated!${NC}"
}

# Make functions available for sourcing
export -f generate_sitemap generate_rss 