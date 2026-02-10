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

declare -gA BSSG_RAM_RSS_FULL_CONTENT_CACHE=()
declare -g BSSG_RAM_RSS_FULL_CONTENT_CACHE_READY=false
declare -gA BSSG_RAM_RSS_PUBDATE_CACHE=()
declare -gA BSSG_RAM_RSS_UPDATED_ISO_CACHE=()
declare -gA BSSG_RAM_RSS_URL_CACHE=()
declare -gA BSSG_RAM_RSS_ITEM_XML_CACHE=()
declare -g BSSG_RAM_RSS_METADATA_CACHE_READY=false

_normalize_relative_url_path() {
    local path="$1"
    while [[ "$path" == */ ]]; do
        path="${path%/}"
    done
    path="${path#/}"
    if [ -z "$path" ]; then
        printf '/'
    else
        printf '/%s/' "$path"
    fi
}

_ram_strip_frontmatter_for_rss() {
    awk '
        BEGIN { in_fm = 0; found_fm = 0; }
        /^---$/ {
            if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
            if (in_fm) { in_fm = 0; next; }
        }
        { if (!in_fm) print; }
    '
}

_ram_cache_full_content_for_file() {
    local file="$1"
    local resolved="$file"

    if declare -F ram_mode_resolve_key > /dev/null; then
        resolved=$(ram_mode_resolve_key "$file")
    fi

    if [[ -z "$resolved" ]]; then
        return 1
    fi

    if [[ -n "${BSSG_RAM_RSS_FULL_CONTENT_CACHE[$resolved]+_}" ]]; then
        return 0
    fi

    if ! declare -F ram_mode_has_file > /dev/null || ! ram_mode_has_file "$resolved"; then
        return 1
    fi

    local raw_content
    raw_content=$(ram_mode_get_content "$resolved")

    local stripped_content
    stripped_content=$(printf '%s\n' "$raw_content" | _ram_strip_frontmatter_for_rss)

    local converted_html
    converted_html=$(convert_markdown_to_html "$stripped_content" "$resolved")
    local convert_status=$?
    if [ $convert_status -ne 0 ] || [ -z "$converted_html" ]; then
        return 1
    fi

    BSSG_RAM_RSS_FULL_CONTENT_CACHE["$resolved"]="$converted_html"
    return 0
}

prepare_ram_rss_full_content_cache() {
    if [ "${BSSG_RAM_MODE:-false}" != true ] || [ "${RSS_INCLUDE_FULL_CONTENT:-false}" != true ]; then
        return 0
    fi

    if [ "$BSSG_RAM_RSS_FULL_CONTENT_CACHE_READY" = true ]; then
        return 0
    fi

    local file_index_data
    file_index_data=$(ram_mode_get_dataset "file_index")
    if [ -z "$file_index_data" ]; then
        BSSG_RAM_RSS_FULL_CONTENT_CACHE_READY=true
        return 0
    fi

    local file filename title date lastmod tags slug image image_caption description author_name author_email
    while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
        [ -z "$file" ] && continue
        _ram_cache_full_content_for_file "$file" > /dev/null || true
    done <<< "$file_index_data"

    BSSG_RAM_RSS_FULL_CONTENT_CACHE_READY=true
}

_ram_prime_rss_metadata_entry() {
    local date="$1"
    local lastmod="$2"
    local slug="$3"
    local rss_date_fmt="$4"
    local build_timestamp_iso="$5"
    local source_file="$6"

    if [ -n "$date" ] && [[ -z "${BSSG_RAM_RSS_PUBDATE_CACHE[$date]+_}" ]]; then
        BSSG_RAM_RSS_PUBDATE_CACHE["$date"]=$(format_date "$date" "$rss_date_fmt")
    fi

    if [ -n "$lastmod" ] && [[ -z "${BSSG_RAM_RSS_UPDATED_ISO_CACHE[$lastmod]+_}" ]]; then
        local updated_date_iso
        updated_date_iso=$(format_date "$lastmod" "%Y-%m-%dT%H:%M:%S%z")
        if [[ "$updated_date_iso" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
            updated_date_iso="${updated_date_iso::${#updated_date_iso}-2}:${BASH_REMATCH[2]}"
        fi
        [ -z "$updated_date_iso" ] && updated_date_iso="$build_timestamp_iso"
        BSSG_RAM_RSS_UPDATED_ISO_CACHE["$lastmod"]="$updated_date_iso"
    fi

    if [ -n "$date" ] && [ -n "$slug" ]; then
        local url_key="${date}|${slug}"
        if [[ -z "${BSSG_RAM_RSS_URL_CACHE[$url_key]+_}" ]]; then
            local year month day formatted_path item_url
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                if [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
                    echo "Warning: Invalid date format '$date' for file $source_file, cannot precompute RSS URL." >&2
                fi
                return 1
            fi
            formatted_path="${URL_SLUG_FORMAT//Year/$year}"
            formatted_path="${formatted_path//Month/$month}"
            formatted_path="${formatted_path//Day/$day}"
            formatted_path="${formatted_path//slug/$slug}"
            item_url=$(_normalize_relative_url_path "$formatted_path")
            BSSG_RAM_RSS_URL_CACHE["$url_key"]=$(fix_url "$item_url")
        fi
    fi

    return 0
}

prepare_ram_rss_metadata_cache() {
    if [ "${BSSG_RAM_MODE:-false}" != true ]; then
        return 0
    fi

    if [ "$BSSG_RAM_RSS_METADATA_CACHE_READY" = true ]; then
        return 0
    fi

    local file_index_data
    file_index_data=$(ram_mode_get_dataset "file_index")
    if [ -z "$file_index_data" ]; then
        BSSG_RAM_RSS_METADATA_CACHE_READY=true
        return 0
    fi

    local rss_date_fmt="%a, %d %b %Y %H:%M:%S %z"
    local build_timestamp_iso
    build_timestamp_iso=$(format_date "now" "%Y-%m-%dT%H:%M:%S%z")
    if [[ "$build_timestamp_iso" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
        build_timestamp_iso="${build_timestamp_iso::${#build_timestamp_iso}-2}:${BASH_REMATCH[2]}"
    fi

    local file filename title date lastmod tags slug image image_caption description author_name author_email
    while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
        [ -z "$file" ] && continue
        _ram_prime_rss_metadata_entry "$date" "$lastmod" "$slug" "$rss_date_fmt" "$build_timestamp_iso" "$file" >/dev/null || true
    done <<< "$file_index_data"

    BSSG_RAM_RSS_METADATA_CACHE_READY=true
}

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

# Fast path for RAM datasets: pick max YYYY-MM-DD from a given field without external sort/head.
_ram_latest_date_from_dataset() {
    local dataset="$1"
    local field_index="$2"
    local date_format="${3:-%Y-%m-%d}"

    local latest_date_str
    latest_date_str=$(printf '%s\n' "$dataset" | awk -F'|' -v field_index="$field_index" '
        NF {
            value = substr($field_index, 1, 10)
            if (value != "" && value > max_date) {
                max_date = value
            }
        }
        END {
            if (max_date != "") {
                print max_date
            }
        }
    ')

    if [ -n "$latest_date_str" ]; then
        printf '%s\n' "$latest_date_str"
    else
        format_date "now" "$date_format"
    fi
}

_generate_sitemap_with_awk_inputs() {
    local sitemap="$1"
    local file_index_input="$2"
    local primary_pages_input="$3"
    local secondary_pages_input="$4"
    local tags_index_input="$5"
    local authors_index_input="$6"
    local latest_post_mod_date="$7"
    local latest_tag_page_mod_date="$8"
    local latest_author_page_mod_date="$9"
    local sitemap_date_fmt="${10:-%Y-%m-%d}"

    # Determine the best awk command locally to avoid potential scoping issues with AWK_CMD.
    local effective_awk_cmd="awk"
    if command -v gawk > /dev/null 2>&1; then
        effective_awk_cmd="gawk"
    fi

    "$effective_awk_cmd" -v site_url="$SITE_URL" \
        -v url_slug_format="$URL_SLUG_FORMAT" \
        -v latest_post_mod_date="$latest_post_mod_date" \
        -v latest_tag_page_mod_date="$latest_tag_page_mod_date" \
        -v latest_author_page_mod_date="$latest_author_page_mod_date" \
        -v enable_author_pages="${ENABLE_AUTHOR_PAGES:-true}" \
        -v sitemap_date_fmt="$sitemap_date_fmt" \
        -F'|' \
        -f - \
        "$file_index_input" "$primary_pages_input" "$secondary_pages_input" "$tags_index_input" "$authors_index_input" <<'AWK_EOF' > "$sitemap"
# AWK script for sitemap generation.
BEGIN {
    OFS = ""
    print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    print "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"

    # Homepage
    print "    <url>"
    print "        <loc>" fix_url_awk("/", site_url) "</loc>"
    print "        <lastmod>" latest_post_mod_date "</lastmod>"
    print "        <changefreq>daily</changefreq>"
    print "        <priority>1.0</priority>"
    print "    </url>"
}

function fix_url_awk(path, base_url) {
    if (substr(path, 1, 1) == "/") {
        sub(/\/$/, "", base_url)
        sub(/^\/+/, "/", path)
        sub(/\/index\.html$/, "/", path)
        if (substr(path, length(path), 1) != "/") {
            path = path "/"
        }
        if (base_url == "" || base_url ~ /^http:\/\/localhost(:[0-9]+)?$/) {
            return path
        } else {
            return base_url path
        }
    } else {
        return path
    }
}

# Process file_index (posts).
FILENAME == ARGV[1] {
    file = $1
    date = $4
    lastmod = $5
    slug = $7
    if (length(file) == 0 || length(date) == 0 || length(lastmod) == 0 || length(slug) == 0) next

    year = substr(date, 1, 4)
    month = substr(date, 6, 2)
    day = substr(date, 9, 2)
    if (year ~ /^[0-9]{4}$/ && month ~ /^[0-9]{2}$/ && day ~ /^[0-9]{2}$/) {
        formatted_path = url_slug_format
        gsub(/Year/, year, formatted_path)
        gsub(/Month/, month, formatted_path)
        gsub(/Day/, day, formatted_path)
        gsub(/slug/, slug, formatted_path)
        item_url = "/" formatted_path
        sub(/\/+$/, "/", item_url)

        mod_time = substr(lastmod, 1, 10)
        if (mod_time == "") next

        print "    <url>"
        print "        <loc>" fix_url_awk(item_url, site_url) "</loc>"
        print "        <lastmod>" mod_time "</lastmod>"
        print "        <changefreq>weekly</changefreq>"
        print "        <priority>0.8</priority>"
        print "    </url>"
    }
}

# Process primary pages.
FILENAME == ARGV[2] {
    url = $2
    date = $3
    if (length(url) == 0 || length(date) == 0) next
    sitemap_url = url
    sub(/index\.html$/, "", sitemap_url)
    sub(/\/+$/, "/", sitemap_url)
    mod_time = substr(date, 1, 10)
    if (mod_time == "") next
    print "    <url>"
    print "        <loc>" fix_url_awk(sitemap_url, site_url) "</loc>"
    print "        <lastmod>" mod_time "</lastmod>"
    print "        <changefreq>monthly</changefreq>"
    print "        <priority>0.7</priority>"
    print "    </url>"
}

# Process secondary pages.
FILENAME == ARGV[3] {
    url = $2
    date = $3
    if (length(url) == 0 || length(date) == 0) next
    sitemap_url = url
    sub(/index\.html$/, "", sitemap_url)
    sub(/\/+$/, "/", sitemap_url)
    mod_time = substr(date, 1, 10)
    if (mod_time == "") next
    print "    <url>"
    print "        <loc>" fix_url_awk(sitemap_url, site_url) "</loc>"
    print "        <lastmod>" mod_time "</lastmod>"
    print "        <changefreq>monthly</changefreq>"
    print "        <priority>0.6</priority>"
    print "    </url>"
}

# Process tags index.
FILENAME == ARGV[4] {
    tag_slug = $2
    if (length(tag_slug) == 0) next
    if (!(tag_slug in processed_tags)) {
        processed_tags[tag_slug] = 1
        item_url = "/tags/" tag_slug "/"
        print "    <url>"
        print "        <loc>" fix_url_awk(item_url, site_url) "</loc>"
        print "        <lastmod>" latest_tag_page_mod_date "</lastmod>"
        print "        <changefreq>weekly</changefreq>"
        print "        <priority>0.5</priority>"
        print "    </url>"
    }
}

# Process authors index.
FILENAME == ARGV[5] && enable_author_pages == "true" {
    author_slug = $2
    if (length(author_slug) == 0) next
    if (!(author_slug in processed_authors)) {
        processed_authors[author_slug] = 1

        if (!authors_index_added) {
            authors_index_added = 1
            print "    <url>"
            print "        <loc>" fix_url_awk("/authors/", site_url) "</loc>"
            print "        <lastmod>" latest_author_page_mod_date "</lastmod>"
            print "        <changefreq>weekly</changefreq>"
            print "        <priority>0.6</priority>"
            print "    </url>"
        }

        item_url = "/authors/" author_slug "/"
        print "    <url>"
        print "        <loc>" fix_url_awk(item_url, site_url) "</loc>"
        print "        <lastmod>" latest_author_page_mod_date "</lastmod>"
        print "        <changefreq>weekly</changefreq>"
        print "        <priority>0.5</priority>"
        print "    </url>"
    }
}

END {
    print "</urlset>"
}
AWK_EOF
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

    local escaped_feed_title escaped_feed_description feed_link feed_atom_link channel_last_build_date
    escaped_feed_title=$(html_escape "$feed_title")
    escaped_feed_description=$(html_escape "$feed_description")
    feed_link=$(fix_url "$feed_link_rel")
    feed_atom_link=$(fix_url "$feed_atom_link_rel")
    channel_last_build_date=$(format_date "now" "$rss_date_fmt")

    exec 4> "$output_file" || return 1
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8" ?>' \
        '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">' \
        '<channel>' \
        "    <title>${escaped_feed_title}</title>" \
        "    <link>${feed_link}</link>" \
        "    <description>${escaped_feed_description}</description>" \
        "    <language>${SITE_LANG:-en}</language>" \
        "    <lastBuildDate>${channel_last_build_date}</lastBuildDate>" \
        "    <atom:link href=\"${feed_atom_link}\" rel=\"self\" type=\"application/rss+xml\" />" >&4

    # Process the provided post data
    while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
        # Ignore blank trailing lines from callers.
        if [ -z "$file" ] && [ -z "$filename" ] && [ -z "$title" ] && [ -z "$date" ] && [ -z "$lastmod" ] && [ -z "$tags" ] && [ -z "$slug" ] && [ -z "$image" ] && [ -z "$image_caption" ] && [ -z "$description" ] && [ -z "$author_name" ] && [ -z "$author_email" ]; then
            continue
        fi
        # Skip if essential fields are missing (robustness)
        if [ -z "$file" ] || [ -z "$title" ] || [ -z "$date" ] || [ -z "$lastmod" ] || [ -z "$slug" ]; then
            echo "Warning: Skipping RSS item due to missing fields in input line: file=$file, title=$title, date=$date, lastmod=$lastmod, slug=$slug" >&2
            continue
        fi

        local rss_item_cache_key=""
        if [ "${BSSG_RAM_MODE:-false}" = true ]; then
            rss_item_cache_key="${RSS_INCLUDE_FULL_CONTENT:-false}|${file}|${date}|${lastmod}|${slug}|${title}"
            if [[ -n "${BSSG_RAM_RSS_ITEM_XML_CACHE[$rss_item_cache_key]+_}" ]]; then
                printf '%s' "${BSSG_RAM_RSS_ITEM_XML_CACHE[$rss_item_cache_key]}" >&4
                continue
            fi
        fi

        # Format dates and URL (RAM mode caches repeated values across many tag feeds).
        local pub_date updated_date_iso full_url
        if [ "${BSSG_RAM_MODE:-false}" = true ]; then
            _ram_prime_rss_metadata_entry "$date" "$lastmod" "$slug" "$rss_date_fmt" "$build_timestamp_iso" "$file" || {
                echo "Warning: Invalid date format '$date' for file $file, cannot generate URL." >&2
                continue
            }
            pub_date="${BSSG_RAM_RSS_PUBDATE_CACHE[$date]}"
            updated_date_iso="${BSSG_RAM_RSS_UPDATED_ISO_CACHE[$lastmod]}"
            full_url="${BSSG_RAM_RSS_URL_CACHE[${date}|${slug}]}"
        else
            pub_date=$(format_date "$date" "$rss_date_fmt")
            updated_date_iso=$(format_date "$lastmod" "%Y-%m-%dT%H:%M:%S%z")
            if [[ "$updated_date_iso" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
                updated_date_iso="${updated_date_iso::${#updated_date_iso}-2}:${BASH_REMATCH[2]}"
            fi
            [ -z "$updated_date_iso" ] && updated_date_iso="$build_timestamp_iso"

            local year month day formatted_path item_url
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                echo "Warning: Invalid date format '$date' for file $file, cannot generate URL." >&2
                continue
            fi
            formatted_path="${URL_SLUG_FORMAT//Year/$year}"
            formatted_path="${formatted_path//Month/$month}"
            formatted_path="${formatted_path//Day/$day}"
            formatted_path="${formatted_path//slug/$slug}"
            item_url=$(_normalize_relative_url_path "$formatted_path")
            full_url=$(fix_url "$item_url")
        fi

        # --- RSS Item Description Enhancement ---
        local item_description_content=""
        local figure_part=""
        local caption_part=""
        local content_part=""
        local escaped_title
        escaped_title=$(html_escape "$title")

        # Build figure part
        if [ -n "$image" ]; then
            local img_src
            [[ "$image" =~ ^https?:// ]] && img_src="$image" || img_src=$(fix_url "$image")
            # Escape alt/title attributes safely using html_escape from utils.sh
            local img_alt="$escaped_title"
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
            if [ "${BSSG_RAM_MODE:-false}" = true ]; then
                local resolved_file="$file"
                if declare -F ram_mode_resolve_key > /dev/null; then
                    resolved_file=$(ram_mode_resolve_key "$file")
                fi

                if _ram_cache_full_content_for_file "$resolved_file"; then
                    content_part="${BSSG_RAM_RSS_FULL_CONTENT_CACHE[$resolved_file]}"
                else
                    # RAM mode is memory-only: never fall back to disk cache reads.
                    if [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
                        echo "Warning: RAM content not available for RSS item ($file). Falling back to excerpt." >&2
                    fi
                    content_part="$description"
                fi
            else
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

        local rss_item_xml
        rss_item_xml="    <item>
        <title>${escaped_title}</title>
        <link>${full_url}</link>
        <guid isPermaLink=\"true\">${full_url}</guid>
        <pubDate>${pub_date}</pubDate>
        <atom:updated>${updated_date_iso}</atom:updated>
        <description>${final_description}</description>
"
        if [ -n "$author_element" ]; then
            rss_item_xml+="${author_element}"$'\n'
        fi
        rss_item_xml+="    </item>
"

        printf '%s' "$rss_item_xml" >&4

        if [ "${BSSG_RAM_MODE:-false}" = true ]; then
            BSSG_RAM_RSS_ITEM_XML_CACHE["$rss_item_cache_key"]="$rss_item_xml"
        fi
    done <<< "$post_data_input"

    # Close the RSS feed
    printf '%s\n' '</channel>' '</rss>' >&4
    exec 4>&-

    if [ "${BSSG_RAM_MODE:-false}" != true ] || [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
        echo -e "${GREEN}RSS feed generated at $output_file${NC}"
    fi
}
export -f _generate_rss_feed # Export for potential parallel use or sourcing

# Generate RSS feed (Main site feed)
generate_rss() {
    echo -e "${YELLOW}Generating main RSS feed...${NC}"

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local file_index_data
        file_index_data=$(ram_mode_get_dataset "file_index")
        if [ -z "$file_index_data" ]; then
            echo -e "${YELLOW}No file index data in RAM. Skipping RSS generation.${NC}"
            return 0
        fi

        prepare_ram_rss_metadata_cache >/dev/null || true

        local rss="$OUTPUT_DIR/${RSS_FILENAME:-rss.xml}"
        local feed_title="${MSG_RSS_FEED_TITLE:-${SITE_TITLE} - RSS Feed}"
        local feed_desc="${MSG_RSS_FEED_DESCRIPTION:-${SITE_DESCRIPTION}}"
        local feed_link_rel="/"
        local feed_atom_link_rel="/${RSS_FILENAME:-rss.xml}"
        local rss_item_limit=${RSS_ITEM_LIMIT:-15}
        local sorted_posts
        sorted_posts=$(printf '%s\n' "$file_index_data" | awk 'NF' | sort -t'|' -k4,4r -k5,5r | head -n "$rss_item_limit")
        _generate_rss_feed "$rss" "$feed_title" "$feed_desc" "$feed_link_rel" "$feed_atom_link_rel" "$sorted_posts"
        return 0
    fi

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

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local sitemap="$OUTPUT_DIR/sitemap.xml"
        local file_index_data tags_index_data authors_index_data primary_pages_data secondary_pages_data
        file_index_data=$(ram_mode_get_dataset "file_index")
        tags_index_data=$(ram_mode_get_dataset "tags_index")
        authors_index_data=$(ram_mode_get_dataset "authors_index")
        primary_pages_data=$(ram_mode_get_dataset "primary_pages")
        secondary_pages_data=$(ram_mode_get_dataset "secondary_pages")

        local latest_post_mod_date latest_tag_page_mod_date latest_author_page_mod_date
        latest_post_mod_date=$(_ram_latest_date_from_dataset "$file_index_data" 5 "%Y-%m-%d")
        latest_tag_page_mod_date=$(_ram_latest_date_from_dataset "$tags_index_data" 5 "%Y-%m-%d")
        latest_author_page_mod_date=$(_ram_latest_date_from_dataset "$authors_index_data" 6 "%Y-%m-%d")

        [ -z "$latest_tag_page_mod_date" ] && latest_tag_page_mod_date="$latest_post_mod_date"
        [ -z "$latest_author_page_mod_date" ] && latest_author_page_mod_date="$latest_post_mod_date"

        _generate_sitemap_with_awk_inputs \
            "$sitemap" \
            <(printf '%s\n' "$file_index_data") \
            <(printf '%s\n' "$primary_pages_data") \
            <(printf '%s\n' "$secondary_pages_data") \
            <(printf '%s\n' "$tags_index_data") \
            <(printf '%s\n' "$authors_index_data") \
            "$latest_post_mod_date" \
            "$latest_tag_page_mod_date" \
            "$latest_author_page_mod_date" \
            "%Y-%m-%d"

        echo -e "${GREEN}Sitemap generated!${NC}"
        return 0
    fi

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

    echo "Generating sitemap content using awk..."
    _generate_sitemap_with_awk_inputs \
        "$sitemap" \
        "$file_index" \
        "$primary_pages_cache" \
        "$secondary_pages_cache" \
        "$tags_index" \
        "$authors_index" \
        "$latest_post_mod_date" \
        "$latest_tag_page_mod_date" \
        "$latest_author_page_mod_date" \
        "$sitemap_date_fmt"

    echo -e "${GREEN}Sitemap generated!${NC}"
}

# Export public functions
export -f _normalize_relative_url_path
export -f _ram_strip_frontmatter_for_rss _ram_cache_full_content_for_file prepare_ram_rss_full_content_cache
export -f generate_sitemap generate_rss 
