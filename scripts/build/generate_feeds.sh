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

# Core RSS generation function
# Usage: _generate_rss_feed <output_file> <feed_title> <feed_description> <feed_link_rel> <feed_atom_link_rel> <post_data_input>
# <post_data_input> should be a string containing the filtered, sorted, and limited post data,
# with each line formatted as: file|filename|title|date|lastmod|tags|slug|image|image_caption|description
# Example Call:
#   sorted_posts=$(sort -t'|' -k4,4r "$file_index" | head -n "$rss_item_limit")
#   _generate_rss_feed "$rss" "$feed_title" "$feed_desc" "/" "/rss.xml" "$sorted_posts"
_generate_rss_feed() {
    local output_file="$1"
    local feed_title="$2"
    local feed_description="$3"
    local feed_link_rel="$4" # Relative link for the channel (e.g., "/" or "/tags/tag-slug/")
    local feed_atom_link_rel="$5" # Relative link for the atom:link (e.g., "/rss.xml" or "/tags/tag-slug/rss.xml")
    local post_data_input="$6" # String containing post data lines

    local rss_date_fmt="%a, %d %b %Y %H:%M:%S %z"

    # Get build timestamp in ISO 8601 for atom:updated fallback
    local build_timestamp_iso=$(format_date "now" "%Y-%m-%dT%H:%M:%S%z")
    # Convert RFC-2822 timezone (+0000) to ISO 8601 (+00:00) if needed
    if [[ "$build_timestamp_iso" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
        build_timestamp_iso="${build_timestamp_iso::${#build_timestamp_iso}-2}:${BASH_REMATCH[2]}"
    fi

    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")"

    # Create the RSS feed header
    cat > "$output_file" << EOF
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
    <title>$(html_escape "$feed_title")</title>
    <link>$(fix_url "$feed_link_rel")</link>
    <description>$(html_escape "$feed_description")</description>
    <language>${SITE_LANG:-en}</language>
    <lastBuildDate>$(format_date "now" "$rss_date_fmt")</lastBuildDate>
    <atom:link href="$(fix_url "$feed_atom_link_rel")" rel="self" type="application/rss+xml" />
EOF

    # Process the provided post data
    echo "$post_data_input" | while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
        # Skip if essential fields are missing (robustness)
        if [ -z "$file" ] || [ -z "$title" ] || [ -z "$date" ] || [ -z "$lastmod" ] || [ -z "$slug" ]; then
            echo "Warning: Skipping RSS item due to missing fields in input line: file=$file, title=$title, date=$date, lastmod=$lastmod, slug=$slug" >&2
            continue
        fi

        # Format dates for RSS
        local pub_date=$(format_date "$date" "$rss_date_fmt")
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
        local figure_part=""
        local caption_part=""
        local content_part=""

        # Build figure part
        if [ -n "$image" ]; then
            local img_src
            [[ "$image" =~ ^https?:// ]] && img_src="$image" || img_src=$(fix_url "$image")
            # Escape alt/title attributes safely using html_escape from utils.sh
            local img_alt=$(html_escape "$title")
            local img_title=$(html_escape "$image_caption")
            [ -z "$img_title" ] && img_title="$img_alt" # Use alt if title is empty

            figure_part="<figure><img src=\"${img_src}\" alt=\"${img_alt}\" title=\"${img_title}\">" # Open tags

            if [ -n "$image_caption" ]; then
                local escaped_caption=$(html_escape "$image_caption")
                caption_part="<figcaption>${escaped_caption}</figcaption>" # Caption
            fi
            figure_part="${figure_part}${caption_part}</figure>" # Close figure tag (with caption inside if it exists)
        fi

        # Build content part (excerpt or full)
        if [ "${RSS_INCLUDE_FULL_CONTENT:-false}" = true ]; then
            local raw_content_cache_file="${CACHE_DIR:-.bssg_cache}/content/$(basename "$file")"
            if [ -f "$raw_content_cache_file" ]; then
                local raw_content=$(cat "$raw_content_cache_file")
                local converted_html=$(convert_markdown_to_html "$raw_content" "$file")
                local convert_status=$?
                if [ $convert_status -eq 0 ] && [ -n "$converted_html" ]; then
                    content_part="$converted_html"
                else
                    echo "Warning: Failed to convert markdown to HTML for RSS item ($file, status: $convert_status). Falling back to excerpt." >&2
                    content_part="$description"
                fi
            else
                echo "Warning: Cached raw markdown content file '$raw_content_cache_file' not found for RSS item ($file). Falling back to excerpt." >&2
                content_part="$description"
            fi
        else
            content_part="$description"
        fi

        # Combine parts safely
        item_description_content="${figure_part}${content_part}"

        # Wrap final description in CDATA
        local final_description="<![CDATA[$item_description_content]]>"

        # Determine author for RSS item (with fallback)
        local rss_author_name="${author_name:-${AUTHOR_NAME:-Anonymous}}"
        local rss_author_email="${author_email}"
        
        # Build author element if we have author info
        local author_element=""
        if [ -n "$rss_author_name" ]; then
            if [ -n "$rss_author_email" ]; then
                author_element="        <dc:creator>$(html_escape "$rss_author_name") ($(html_escape "$rss_author_email"))</dc:creator>"
            else
                author_element="        <dc:creator>$(html_escape "$rss_author_name")</dc:creator>"
            fi
        fi

        cat >> "$output_file" << EOF
    <item>
        <title>$(html_escape "$title")</title>
        <link>${full_url}</link>
        <guid isPermaLink="true">${full_url}</guid>
        <pubDate>${pub_date}</pubDate>
        <atom:updated>${updated_date_iso}</atom:updated>
        <description>${final_description}</description>
${author_element}
    </item>
EOF
    done

    # Close the RSS feed
    cat >> "$output_file" << EOF
</channel>
</rss>
EOF

    echo -e "${GREEN}RSS feed generated at $output_file${NC}"
}
export -f _generate_rss_feed # Export for potential parallel use or sourcing

# Generate RSS feed (Main site feed)
generate_rss() {
    echo -e "${YELLOW}Generating main RSS feed...${NC}"

    # Ensure needed functions/vars are available
    if ! command -v convert_markdown_to_html &> /dev/null; then
        echo -e "${RED}Error: convert_markdown_to_html function not found.${NC}" >&2; return 1; fi
    if [ -z "${MD5_CMD:-}" ]; then
        echo -e "${RED}Error: MD5_CMD is not set.${NC}" >&2; return 1; fi
    if [ -z "${CACHE_DIR:-}" ]; then
        echo -e "${RED}Error: CACHE_DIR is not set.${NC}" >&2; return 1; fi

    local rss="$OUTPUT_DIR/${RSS_FILENAME:-rss.xml}"
    local file_index="$CACHE_DIR/file_index.txt"
    local config_hash_file="$CONFIG_HASH_FILE"
    local script_path="$BSSG_SCRIPT_DIR/build/generate_feeds.sh"

    # Determine active locale file
    local active_locale_file=""
    if [ -f "${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh" ]; then
        active_locale_file="${LOCALE_DIR:-locales}/${SITE_LANG:-en}.sh"
    elif [ -f "${LOCALE_DIR:-locales}/en.sh" ]; then
        active_locale_file="${LOCALE_DIR:-locales}/en.sh"
    fi

    # Check if RSS feed needs to be rebuilt (Simplified check)
    local rebuild_needed=false
    if [ "${FORCE_REBUILD:-false}" = true ]; then
        rebuild_needed=true
    elif [ ! -f "$rss" ]; then
        rebuild_needed=true # Rebuild if RSS file doesn't exist
    else
        local rss_mtime=$(get_file_mtime "$rss")
        # Check file index mtime AND config hash mtime
        if { [ -f "$file_index" ] && [ "$(get_file_mtime "$file_index")" -gt "$rss_mtime" ]; } || \
           { [ -f "$config_hash_file" ] && [ "$(get_file_mtime "$config_hash_file")" -gt "$rss_mtime" ]; }; then \
            rebuild_needed=true
        fi
        # Removed checks for script, locale mtime for simplicity, kept config hash check
    fi

    # If no rebuild needed, skip
    if [ "$rebuild_needed" = false ]; then
        echo -e "${GREEN}Main RSS feed is up to date (based on file index), skipping...${NC}"
        return 0
    fi

    if [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index '$file_index' not found. Cannot generate RSS feed.${NC}"
        return 1
    fi

    # Prepare data for the reusable function
    local feed_title="${MSG_RSS_FEED_TITLE:-${SITE_TITLE} - RSS Feed}"
    local feed_desc="${MSG_RSS_FEED_DESCRIPTION:-${SITE_DESCRIPTION}}"
    local feed_link_rel="/"
    local feed_atom_link_rel="/${RSS_FILENAME:-rss.xml}" # Use the config variable
    local rss_item_limit=${RSS_ITEM_LIMIT:-15}

    # Read file_index.txt, sort by original date (field 4), take top N
    # Use lastmod (field 5) as secondary sort key if dates are identical (optional, but good practice)
    local sorted_posts
    sorted_posts=$(sort -t'|' -k4,4r -k5,5r "$file_index" | head -n "$rss_item_limit")

    # Call the reusable function
    # echo "DEBUG: In generate_rss, RSS_FILENAME='${RSS_FILENAME:-rss.xml}', output_file='${rss}'" >&2 # DEBUG
    _generate_rss_feed "$rss" "$feed_title" "$feed_desc" "$feed_link_rel" "$feed_atom_link_rel" "$sorted_posts"

    # The reusable function already prints the success message
    # echo -e "${GREEN}RSS feed generated!${NC}" # Redundant now
}

# Export public functions
export -f generate_rss 

# Generate sitemap.xml
generate_sitemap() {
    echo -e "${YELLOW}Generating sitemap.xml...${NC}"

    local sitemap="$OUTPUT_DIR/sitemap.xml"
    local file_index="$CACHE_DIR/file_index.txt"
    local tags_index="$CACHE_DIR/tags_index.txt"
    local authors_index="$CACHE_DIR/authors_index.txt"
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

    # Check if sitemap needs rebuild (Simplified check)
    local rebuild_needed=false
    if [ "${FORCE_REBUILD:-false}" = true ]; then
        rebuild_needed=true
    elif [ ! -f "$sitemap" ]; then
        rebuild_needed=true # Rebuild if sitemap doesn't exist
    else
        local sitemap_mtime=$(get_file_mtime "$sitemap")
        # Check main content index files
        if [ -f "$file_index" ] && [ "$(get_file_mtime "$file_index")" -gt "$sitemap_mtime" ]; then rebuild_needed=true; fi
        if ! $rebuild_needed && [ -f "$tags_index" ] && [ "$(get_file_mtime "$tags_index")" -gt "$sitemap_mtime" ]; then rebuild_needed=true; fi
        if ! $rebuild_needed && [ -f "$authors_index" ] && [ "$(get_file_mtime "$authors_index")" -gt "$sitemap_mtime" ]; then rebuild_needed=true; fi
        if ! $rebuild_needed && [ -f "$primary_pages_cache" ] && [ "$(get_file_mtime "$primary_pages_cache")" -gt "$sitemap_mtime" ]; then rebuild_needed=true; fi
        if ! $rebuild_needed && [ -f "$secondary_pages_cache" ] && [ "$(get_file_mtime "$secondary_pages_cache")" -gt "$sitemap_mtime" ]; then rebuild_needed=true; fi
        # Removed checks for script, config, locale mtime for simplicity to avoid sourcing errors
    fi

    # If no rebuild needed based on simple checks, skip
        if [ "$rebuild_needed" = false ]; then
        echo -e "${GREEN}Sitemap is up to date (based on content indexes), skipping...${NC}"
            return 0
    fi

    # --- Pre-calculate latest dates (Still needed for Homepage/Tags/Authors) ---
    local latest_post_mod_date=$(get_latest_mod_date "$file_index" 5 "" "$sitemap_date_fmt")
    local latest_tag_page_mod_date=$(get_latest_mod_date "$tags_index" 5 "" "$sitemap_date_fmt") # Assumes lastmod is relevant field in tags_index
    local latest_author_page_mod_date=$(get_latest_mod_date "$authors_index" 6 "" "$sitemap_date_fmt") # Field 6 is lastmod in authors_index

    # --- Generate Sitemap using AWK --- START ---
    echo "Generating sitemap content using awk..."

    # Determine the best awk command locally to avoid potential scoping issues with AWK_CMD
    local effective_awk_cmd="awk" # Default to standard awk
    if command -v gawk > /dev/null 2>&1; then
        effective_awk_cmd="gawk" # Prefer gawk if available
    fi

    # Use awk with a here-doc for the script for cleaner quoting
    # Use the locally determined effective_awk_cmd
    "$effective_awk_cmd" -v site_url="$SITE_URL" \
        -v url_slug_format="$URL_SLUG_FORMAT" \
        -v latest_post_mod_date="$latest_post_mod_date" \
        -v latest_tag_page_mod_date="$latest_tag_page_mod_date" \
        -v latest_author_page_mod_date="$latest_author_page_mod_date" \
        -v enable_author_pages="${ENABLE_AUTHOR_PAGES:-true}" \
        -v sitemap_date_fmt="$sitemap_date_fmt" \
        -F'|' \
        -f - \
        "$file_index" "$primary_pages_cache" "$secondary_pages_cache" "$tags_index" "$authors_index" <<'AWK_EOF' > "$sitemap"
# AWK script for sitemap generation (fed via here-doc)
BEGIN {
    OFS=""; # No output field separator needed for XML
    print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
    print "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">";

    # Homepage
    print "    <url>";
    print "        <loc>" fix_url_awk("/", site_url) "</loc>";
    print "        <lastmod>" latest_post_mod_date "</lastmod>";
    print "        <changefreq>daily</changefreq>";
    print "        <priority>1.0</priority>";
    print "    </url>";
}

# Custom function to replicate fix_url shell function logic
function fix_url_awk(path, base_url) {
    if (substr(path, 1, 1) == "/") {
        # Remove trailing slash from base_url if present
        sub(/\/$/, "", base_url);
        # Ensure path doesnt start with //
        sub(/^\/+/, "/", path);
        # Remove index.html if present
        sub(/\/index\.html$/, "/", path);
        # Ensure trailing slash
        if (substr(path, length(path), 1) != "/") {
            path = path "/";
        }
        # Handle case where base_url is empty or just http://localhost* - skip prepending
        if (base_url == "" || base_url ~ /^http:\/\/localhost(:[0-9]+)?$/) {
            return path
        } else {
            return base_url path;
        }
    } else {
        return path; # Should not happen for sitemap paths?
    }
}

# Process file_index.txt (Posts)
FILENAME == ARGV[1] {
    file=$1; filename=$2; title=$3; date=$4; lastmod=$5; tags=$6; slug=$7;
    if (length(file) == 0 || length(date) == 0 || length(lastmod) == 0 || length(slug) == 0) next;

    year=substr(date, 1, 4);
    month=substr(date, 6, 2);
    day=substr(date, 9, 2);
    # Ensure valid numbers? Basic check:
    if (year ~ /^[0-9]{4}$/ && month ~ /^[0-9]{2}$/ && day ~ /^[0-9]{2}$/) {
        formatted_path = url_slug_format;
        gsub(/Year/, year, formatted_path);
        gsub(/Month/, month, formatted_path);
        gsub(/Day/, day, formatted_path);
        gsub(/slug/, slug, formatted_path);
        item_url = "/" formatted_path;
        # Clean URL logic from shell script
        sub(/\/+$/, "/", item_url);

        mod_time = substr(lastmod, 1, 10); # Extract YYYY-MM-DD from lastmod ($5)
        if (mod_time == "") next; # Skip if date is invalid/empty

        print "    <url>";
        print "        <loc>" fix_url_awk(item_url, site_url) "</loc>";
        print "        <lastmod>" mod_time "</lastmod>";
        print "        <changefreq>weekly</changefreq>";
        print "        <priority>0.8</priority>";
        print "    </url>";
    }
}

# Process primary_pages.tmp
FILENAME == ARGV[2] {
    url=$2; date=$3; # $1=_, $4=source_file
    if (length(url) == 0 || length(date) == 0) next;
    sitemap_url = url;
    sub(/index\.html$/, "", sitemap_url); # Remove index.html
    sub(/\/+$/, "/", sitemap_url);      # Ensure trailing slash
    mod_time = substr(date, 1, 10); # Extract YYYY-MM-DD from date ($3)
    if (mod_time == "") next; # Skip if date is invalid/empty
    print "    <url>";
    print "        <loc>" fix_url_awk(sitemap_url, site_url) "</loc>";
    print "        <lastmod>" mod_time "</lastmod>";
    print "        <changefreq>monthly</changefreq>";
    print "        <priority>0.7</priority>";
    print "    </url>";
}

# Process secondary_pages.tmp
FILENAME == ARGV[3] {
    url=$2; date=$3; # $1=_, $4=source_file
    if (length(url) == 0 || length(date) == 0) next;
    sitemap_url = url;
    sub(/index\.html$/, "", sitemap_url);
    sub(/\/+$/, "/", sitemap_url);
    mod_time = substr(date, 1, 10); # Extract YYYY-MM-DD from date ($3)
    if (mod_time == "") next; # Skip if date is invalid/empty
    print "    <url>";
    print "        <loc>" fix_url_awk(sitemap_url, site_url) "</loc>";
    print "        <lastmod>" mod_time "</lastmod>";
    print "        <changefreq>monthly</changefreq>";
    print "        <priority>0.6</priority>"; # Lower priority for secondary?
    print "    </url>";
}

# Process tags_index.txt (Tag Pages)
FILENAME == ARGV[4] {
    tag=$1; tag_slug=$2; # $5 = lastmod for posts with this tag
    if (length(tag_slug) == 0) next;
    # Check if tag slug already processed
    if ( !(tag_slug in processed_tags) ) {
         processed_tags[tag_slug] = 1; # Mark as processed
         item_url = "/tags/" tag_slug "/";
         # Use the overall latest tag mod date for all tag pages?
         mod_time = latest_tag_page_mod_date;
         print "    <url>";
         print "        <loc>" fix_url_awk(item_url, site_url) "</loc>";
         print "        <lastmod>" mod_time "</lastmod>";
         print "        <changefreq>weekly</changefreq>";
         print "        <priority>0.5</priority>";
         print "    </url>";
    }
}

# Process authors_index.txt (Author Pages) - only if author pages are enabled
FILENAME == ARGV[5] && enable_author_pages == "true" {
    author_name=$1; author_slug=$2; # $6 = lastmod for posts with this author
    if (length(author_slug) == 0) next;
    # Check if author slug already processed
    if ( !(author_slug in processed_authors) ) {
         processed_authors[author_slug] = 1; # Mark as processed
         
         # Add main authors index page (only once)
         if (!authors_index_added) {
             authors_index_added = 1;
             print "    <url>";
             print "        <loc>" fix_url_awk("/authors/", site_url) "</loc>";
             print "        <lastmod>" latest_author_page_mod_date "</lastmod>";
             print "        <changefreq>weekly</changefreq>";
             print "        <priority>0.6</priority>";
             print "    </url>";
         }
         
         # Add individual author page
         item_url = "/authors/" author_slug "/";
         mod_time = latest_author_page_mod_date;
         print "    <url>";
         print "        <loc>" fix_url_awk(item_url, site_url) "</loc>";
         print "        <lastmod>" mod_time "</lastmod>";
         print "        <changefreq>weekly</changefreq>";
         print "        <priority>0.5</priority>";
         print "    </url>";
    }
}

END {
    print "</urlset>";
}
AWK_EOF
    # awk exit status check - optional
    # local awk_status=$?
    # if [ $awk_status -ne 0 ]; then
    #     echo -e "${RED}Error: awk script for sitemap generation failed with status $awk_status${NC}" >&2
    #     # Decide whether to return 1 or continue
    # fi

    # --- Generate Sitemap using AWK --- END ---

    echo -e "${GREEN}Sitemap generated!${NC}"
}

# Export public functions
export -f generate_sitemap generate_rss 