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

declare -gA BSSG_RAM_TAG_POST_SLUGS_BY_SLUG=()
declare -gA BSSG_RAM_TAG_POST_COUNT_BY_SLUG=()
declare -gA BSSG_RAM_TAG_ARTICLE_HTML_BY_SLUG=()
declare -gA BSSG_RAM_RSS_TEMPLATE_BY_SLUG=()
declare -g BSSG_RAM_TAG_DISPLAY_DATE_FORMAT=""
declare -g BSSG_RAM_TAG_HEADER_BASE=""
declare -g BSSG_RAM_TAG_FOOTER_CONTENT=""

_bssg_tags_now_ms() {
    if declare -F _bssg_ram_timing_now_ms > /dev/null; then
        _bssg_ram_timing_now_ms
        return
    fi

    if [ -n "${EPOCHREALTIME:-}" ]; then
        local epoch_norm sec frac ms_part
        # Some locales expose EPOCHREALTIME with ',' instead of '.' as decimal separator.
        epoch_norm="${EPOCHREALTIME/,/.}"
        if [[ "$epoch_norm" =~ ^([0-9]+)([.][0-9]+)?$ ]]; then
            sec="${BASH_REMATCH[1]}"
            frac="${BASH_REMATCH[2]#.}"
            frac="${frac}000"
            ms_part="${frac:0:3}"
            printf '%s\n' $(( 10#$sec * 1000 + 10#$ms_part ))
            return
        fi
    fi

    if command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf("%.0f\n", time()*1000)'
    else
        printf '%s\n' $(( $(date +%s) * 1000 ))
    fi
}

_bssg_tags_format_ms() {
    local ms="${1:-0}"
    printf '%d.%03ds' $((ms / 1000)) $((ms % 1000))
}

_write_tag_rss_from_cached_items_ram() {
    local output_file="$1"
    local feed_link_rel="$2"
    local feed_atom_link_rel="$3"
    local tag="$4"
    local rss_items_xml="$5"

    local feed_title="${SITE_TITLE} - ${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag"
    local feed_description="${MSG_POSTS_TAGGED_WITH:-"Posts tagged with"}: $tag"
    local rss_date_fmt="%a, %d %b %Y %H:%M:%S %z"

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

    if [ -n "$rss_items_xml" ]; then
        printf '%s' "$rss_items_xml" >&4
    fi

    printf '%s\n' '</channel>' '</rss>' >&4
    exec 4>&-

    if [ "${BSSG_RAM_MODE:-false}" != true ] || [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
        echo -e "${GREEN}RSS feed generated at $output_file${NC}"
    fi
}

_process_single_tag_page_ram() {
    local tag_url="$1"
    local tag="$2"
    local tag_page_html_file="$OUTPUT_DIR/tags/$tag_url/index.html"
    local tag_rss_file="$OUTPUT_DIR/tags/$tag_url/${RSS_FILENAME:-rss.xml}"
    local tag_page_rel_url="/tags/${tag_url}/"
    local tag_rss_rel_url="/tags/${tag_url}/${RSS_FILENAME:-rss.xml}"
    mkdir -p "$(dirname "$tag_page_html_file")"

    local header_content="$BSSG_RAM_TAG_HEADER_BASE"
    header_content=${header_content//\{\{page_title\}\}/"${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag"}
    header_content=${header_content//\{\{page_url\}\}/"$tag_page_rel_url"}
    if [ "${ENABLE_TAG_RSS:-false}" = true ]; then
        header_content=${header_content//<!-- bssg:tag_rss_link -->/<link rel="alternate" type="application/rss+xml" title="${SITE_TITLE} - Posts tagged with ${tag}" href="${SITE_URL}${tag_rss_rel_url}">}
    else
        header_content=${header_content//<!-- bssg:tag_rss_link -->/}
    fi
    local schema_json_ld
    schema_json_ld=$(cat <<EOF
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
)
    header_content=${header_content//\{\{schema_json_ld\}\}/"$schema_json_ld"}
    local footer_content="$BSSG_RAM_TAG_FOOTER_CONTENT"

    exec 3> "$tag_page_html_file"
    printf '%s\n' "$header_content" >&3
    printf '<h1>%s: %s</h1>\n' "${MSG_TAG_PAGE_TITLE:-Posts tagged with}" "$tag" >&3
    printf '<div class="posts-list">\n' >&3

    local rss_item_limit=${RSS_ITEM_LIMIT:-15}
    local rss_count=0
    local cached_rss_items=""
    local rss_all_items_cached=true
    local -a selected_rss_templates=()
    local tag_post_slugs=""
    if [[ -n "${BSSG_RAM_TAG_POST_SLUGS_BY_SLUG[$tag_url]+_}" ]]; then
        tag_post_slugs="${BSSG_RAM_TAG_POST_SLUGS_BY_SLUG[$tag_url]}"
    fi

    local slug cached_article_html rss_template
    while IFS= read -r slug; do
        [ -z "$slug" ] && continue
        cached_article_html="${BSSG_RAM_TAG_ARTICLE_HTML_BY_SLUG[$slug]}"
        if [ -n "$cached_article_html" ]; then
            printf '%s' "$cached_article_html" >&3
        fi
        if [ "${ENABLE_TAG_RSS:-false}" = true ] && [ "$rss_count" -lt "$rss_item_limit" ]; then
            rss_template="${BSSG_RAM_RSS_TEMPLATE_BY_SLUG[$slug]}"
            if [ -n "$rss_template" ]; then
                selected_rss_templates+=("$rss_template")
                if $rss_all_items_cached; then
                    local rss_file rss_filename rss_title rss_date rss_lastmod rss_tags rss_slug rss_image rss_image_caption rss_description rss_author_name rss_author_email
                    IFS='|' read -r rss_file rss_filename rss_title rss_date rss_lastmod rss_tags rss_slug rss_image rss_image_caption rss_description rss_author_name rss_author_email <<< "$rss_template"
                    local rss_item_cache_key="${RSS_INCLUDE_FULL_CONTENT:-false}|${rss_file}|${rss_date}|${rss_lastmod}|${rss_slug}|${rss_title}"
                    local rss_item_xml="${BSSG_RAM_RSS_ITEM_XML_CACHE[$rss_item_cache_key]-}"
                    if [ -n "$rss_item_xml" ]; then
                        cached_rss_items+="$rss_item_xml"
                    else
                        rss_all_items_cached=false
                    fi
                fi
                rss_count=$((rss_count + 1))
            fi
        fi
    done <<< "$tag_post_slugs"

    printf '</div>\n' >&3
    printf '<p><a href="%s/tags/">%s</a></p>\n' "$SITE_URL" "${MSG_ALL_TAGS:-All Tags}" >&3
    printf '%s\n' "$footer_content" >&3
    exec 3>&-

    if [ "${ENABLE_TAG_RSS:-false}" = true ] && [ "${#selected_rss_templates[@]}" -gt 0 ]; then
        if $rss_all_items_cached; then
            _write_tag_rss_from_cached_items_ram "$tag_rss_file" "$tag_page_rel_url" "$tag_rss_rel_url" "$tag" "$cached_rss_items"
        else
            local tag_post_data=""
            local rss_template_entry
            for rss_template_entry in "${selected_rss_templates[@]}"; do
                tag_post_data+="${rss_template_entry//%TAG%/$tag}"$'\n'
            done
            _generate_rss_feed "$tag_rss_file" "${SITE_TITLE} - ${MSG_TAG_PAGE_TITLE:-"Posts tagged with"}: $tag" "${MSG_POSTS_TAGGED_WITH:-"Posts tagged with"}: $tag" "$tag_page_rel_url" "$tag_rss_rel_url" "$tag_post_data"
        fi
    fi
}

_generate_tag_pages_ram() {
    echo -e "${YELLOW}Processing tag pages${NC}${ENABLE_TAG_RSS:+" and RSS feeds"}...${NC}"
    local ram_tags_timing_enabled=false
    if [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
        ram_tags_timing_enabled=true
    fi
    local tags_total_start_ms=0
    local tags_phase_start_ms=0
    local tags_prep_ms=0
    local tags_render_ms=0
    local tags_index_ms=0
    local tags_total_ms=0
    if [ "$ram_tags_timing_enabled" = true ]; then
        tags_total_start_ms="$(_bssg_tags_now_ms)"
        tags_phase_start_ms="$tags_total_start_ms"
    fi

    local tags_index_data
    tags_index_data=$(ram_mode_get_dataset "tags_index")
    local main_tags_index_output="$OUTPUT_DIR/tags/index.html"

    mkdir -p "$OUTPUT_DIR/tags"

    if [ -z "$tags_index_data" ]; then
        echo -e "${YELLOW}No tags found in RAM index. Skipping tag page generation.${NC}"
        return 0
    fi

    BSSG_RAM_TAG_POST_SLUGS_BY_SLUG=()
    BSSG_RAM_TAG_POST_COUNT_BY_SLUG=()
    BSSG_RAM_TAG_ARTICLE_HTML_BY_SLUG=()
    BSSG_RAM_RSS_TEMPLATE_BY_SLUG=()
    declare -A tag_name_by_slug=()
    local sorted_tag_urls=()
    declare -A rss_prefill_slug_set=()
    declare -A rss_prefill_slug_hits=()
    local rss_prefill_slugs=()
    local rss_prefill_occurrences=0
    local rss_item_limit="${RSS_ITEM_LIMIT:-15}"
    local rss_prefill_min_hits="${RAM_RSS_PREFILL_MIN_HITS:-2}"
    local rss_prefill_max_posts="${RAM_RSS_PREFILL_MAX_POSTS:-24}"
    if ! [[ "$rss_prefill_min_hits" =~ ^[0-9]+$ ]] || [ "$rss_prefill_min_hits" -lt 1 ]; then
        rss_prefill_min_hits=1
    fi
    if ! [[ "$rss_prefill_max_posts" =~ ^[0-9]+$ ]]; then
        rss_prefill_max_posts=24
    fi
    declare -A seen_post_slugs=()
    local display_date_format="$DATE_FORMAT"
    if [ "${SHOW_TIMEZONE:-false}" = false ]; then
        display_date_format=$(echo "$display_date_format" | sed -e 's/%[zZ]//g' -e 's/[[:space:]]*$//')
    fi
    BSSG_RAM_TAG_DISPLAY_DATE_FORMAT="$display_date_format"

    # Prime per-post caches once from file_index (one row per post), then build
    # lightweight tag->post mappings from tags_index (many rows per post).
    local file_index_data
    file_index_data=$(ram_mode_get_dataset "file_index")

    local can_prime_rss_metadata=false
    local rss_date_fmt="%a, %d %b %Y %H:%M:%S %z"
    local build_timestamp_iso=""
    if [ "${ENABLE_TAG_RSS:-false}" = true ] && declare -F _ram_prime_rss_metadata_entry > /dev/null; then
        can_prime_rss_metadata=true
        build_timestamp_iso=$(format_date "now" "%Y-%m-%dT%H:%M:%S%z")
        if [[ "$build_timestamp_iso" =~ ([+-][0-9]{2})([0-9]{2})$ ]]; then
            build_timestamp_iso="${build_timestamp_iso::${#build_timestamp_iso}-2}:${BASH_REMATCH[2]}"
        fi
    fi

    local file filename title date lastmod tags slug image image_caption description author_name author_email
    while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
        [ -z "$file" ] && continue
        [ -z "$slug" ] && continue
        [[ -n "${seen_post_slugs[$slug]+_}" ]] && continue
        seen_post_slugs["$slug"]=1

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
        local post_link="/${formatted_path}/"
        local formatted_date
        formatted_date=$(format_date "$date" "$display_date_format")

        local display_author_name="${author_name:-${AUTHOR_NAME:-Anonymous}}"
        local article_html=""
        article_html+='    <article>'$'\n'
        article_html+="        <h3><a href=\"${SITE_URL}${post_link}\">${title}</a></h3>"$'\n'
        article_html+="        <div class=\"meta\">${MSG_PUBLISHED_ON:-Published on} ${formatted_date} ${MSG_BY:-by} <strong>${display_author_name}</strong></div>"$'\n'
        if [ -n "$image" ]; then
            local image_url alt_text figcaption_content
            image_url=$(fix_url "$image")
            alt_text="${image_caption:-$title}"
            figcaption_content="${image_caption:-$title}"
            article_html+='        <figure class="featured-image tag-image">'$'\n'
            article_html+="            <a href=\"${SITE_URL}${post_link}\">"$'\n'
            article_html+="                <img src=\"${image_url}\" alt=\"${alt_text}\" />"$'\n'
            article_html+='            </a>'$'\n'
            article_html+="            <figcaption>${figcaption_content}</figcaption>"$'\n'
            article_html+='        </figure>'$'\n'
        fi
        if [ -n "$description" ]; then
            article_html+='        <div class="summary">'$'\n'
            article_html+="            ${description}"$'\n'
            article_html+='        </div>'$'\n'
        fi
        article_html+='    </article>'$'\n'
        BSSG_RAM_TAG_ARTICLE_HTML_BY_SLUG["$slug"]="$article_html"
        BSSG_RAM_RSS_TEMPLATE_BY_SLUG["$slug"]="${filename}|${filename}|${title}|${date}|${lastmod}|%TAG%|${slug}|${image}|${image_caption}|${description}|${author_name}|${author_email}"

        if $can_prime_rss_metadata; then
            _ram_prime_rss_metadata_entry "$date" "$lastmod" "$slug" "$rss_date_fmt" "$build_timestamp_iso" "$file" >/dev/null || true
        fi
    done <<< "$file_index_data"

    if $can_prime_rss_metadata; then
        BSSG_RAM_RSS_METADATA_CACHE_READY=true
    fi

    # Sort once globally by tag slug, then by publish date/lastmod descending.
    # Aggregate per-tag rows in awk to reduce per-line bash map churn.
    local aggregated_tags_data
    aggregated_tags_data=$(printf '%s\n' "$tags_index_data" | awk 'NF' | LC_ALL=C sort -t'|' -k2,2 -k4,4r -k5,5r | awk -F'|' -v OFS='|' '
        {
            tag = $1
            tag_slug = $2
            post_slug = $7
            if (tag == "" || tag_slug == "") next

            if (current_tag_slug != "" && tag_slug != current_tag_slug) {
                print current_tag_slug, current_tag_name, current_count, current_post_slugs
                current_count = 0
                current_post_slugs = ""
            }

            if (tag_slug != current_tag_slug) {
                current_tag_slug = tag_slug
                current_tag_name = tag
            }

            if (post_slug != "") {
                if (current_post_slugs == "") {
                    current_post_slugs = post_slug
                } else {
                    current_post_slugs = current_post_slugs "," post_slug
                }
            }
            current_count++
        }
        END {
            if (current_tag_slug != "") {
                print current_tag_slug, current_tag_name, current_count, current_post_slugs
            }
        }')

    local tag_slug tag_name tag_count_value tag_post_slugs_csv
    while IFS='|' read -r tag_slug tag_name tag_count_value tag_post_slugs_csv; do
        [ -z "$tag_slug" ] && continue
        tag_name_by_slug["$tag_slug"]="$tag_name"
        BSSG_RAM_TAG_POST_COUNT_BY_SLUG["$tag_slug"]="$tag_count_value"
        local tag_post_slugs_newline=""
        if [ -n "$tag_post_slugs_csv" ]; then
            tag_post_slugs_newline="${tag_post_slugs_csv//,/$'\n'}"
        fi
        BSSG_RAM_TAG_POST_SLUGS_BY_SLUG["$tag_slug"]="$tag_post_slugs_newline"
        sorted_tag_urls+=("$tag_slug")

        if [ "${ENABLE_TAG_RSS:-false}" = true ] && [ -n "$tag_post_slugs_newline" ]; then
            local rss_prefill_count=0
            local rss_prefill_slug=""
            while IFS= read -r rss_prefill_slug; do
                [ -z "$rss_prefill_slug" ] && continue
                rss_prefill_occurrences=$((rss_prefill_occurrences + 1))
                rss_prefill_slug_hits["$rss_prefill_slug"]=$(( ${rss_prefill_slug_hits[$rss_prefill_slug]:-0} + 1 ))
                if [[ -z "${rss_prefill_slug_set[$rss_prefill_slug]+_}" ]]; then
                    rss_prefill_slug_set["$rss_prefill_slug"]=1
                    rss_prefill_slugs+=("$rss_prefill_slug")
                fi
                rss_prefill_count=$((rss_prefill_count + 1))
                if [ "$rss_prefill_count" -ge "$rss_item_limit" ]; then
                    break
                fi
            done <<< "$tag_post_slugs_newline"
        fi
    done <<< "$aggregated_tags_data"

    if [ "${ENABLE_TAG_RSS:-false}" = true ] && [ "$rss_prefill_min_hits" -gt 1 ] && [ "${#rss_prefill_slugs[@]}" -gt 0 ]; then
        local -a rss_prefill_filtered_slugs=()
        local rss_prefill_slug
        for rss_prefill_slug in "${rss_prefill_slugs[@]}"; do
            if [ "${rss_prefill_slug_hits[$rss_prefill_slug]:-0}" -ge "$rss_prefill_min_hits" ]; then
                rss_prefill_filtered_slugs+=("$rss_prefill_slug")
            fi
        done
        if [ "${#rss_prefill_filtered_slugs[@]}" -gt 0 ]; then
            rss_prefill_slugs=("${rss_prefill_filtered_slugs[@]}")
        fi
    fi

    local rss_prefill_pool_count="${#rss_prefill_slugs[@]}"
    if [ "${ENABLE_TAG_RSS:-false}" = true ] && [ "$rss_prefill_max_posts" -gt 0 ] && [ "${#rss_prefill_slugs[@]}" -gt "$rss_prefill_max_posts" ]; then
        local -a rss_prefill_ranked_lines=()
        local rss_prefill_slug
        for rss_prefill_slug in "${rss_prefill_slugs[@]}"; do
            rss_prefill_ranked_lines+=("${rss_prefill_slug_hits[$rss_prefill_slug]:-0}|$rss_prefill_slug")
        done

        local -a rss_prefill_capped_slugs=()
        local rss_prefill_rank_line
        while IFS= read -r rss_prefill_rank_line; do
            [ -z "$rss_prefill_rank_line" ] && continue
            rss_prefill_capped_slugs+=("${rss_prefill_rank_line#*|}")
        done < <(
            printf '%s\n' "${rss_prefill_ranked_lines[@]}" \
            | LC_ALL=C sort -t'|' -k1,1nr -k2,2 \
            | head -n "$rss_prefill_max_posts"
        )

        if [ "${#rss_prefill_capped_slugs[@]}" -gt 0 ]; then
            rss_prefill_slugs=("${rss_prefill_capped_slugs[@]}")
        fi
    fi

    local footer_base="$FOOTER_TEMPLATE"
    footer_base=${footer_base//\{\{current_year\}\}/$(date +%Y)}
    footer_base=${footer_base//\{\{author_name\}\}/"$AUTHOR_NAME"}
    BSSG_RAM_TAG_FOOTER_CONTENT="$footer_base"

    local header_base="$HEADER_TEMPLATE"
    header_base=${header_base//\{\{site_title\}\}/"$SITE_TITLE"}
    header_base=${header_base//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_base=${header_base//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_base=${header_base//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    header_base=${header_base//\{\{og_type\}\}/"website"}
    header_base=${header_base//\{\{site_url\}\}/"$SITE_URL"}
    header_base=${header_base//\{\{og_image\}\}/""}
    header_base=${header_base//\{\{twitter_image\}\}/""}
    BSSG_RAM_TAG_HEADER_BASE="$header_base"

    local tag_count="${#sorted_tag_urls[@]}"
    echo -e "Generating ${GREEN}$tag_count${NC} tag pages from RAM index."

    if [ "${ENABLE_TAG_RSS:-false}" = true ]; then
        if declare -F prepare_ram_rss_metadata_cache > /dev/null; then
            prepare_ram_rss_metadata_cache
        fi
        if [ "${RSS_INCLUDE_FULL_CONTENT:-false}" = true ] && declare -F prepare_ram_rss_full_content_cache > /dev/null; then
            prepare_ram_rss_full_content_cache
        fi

        # Pre-warm RAM RSS item XML cache once in parent process so worker
        # subshells inherit it read-only and avoid rebuilding duplicate items.
        if declare -F _generate_rss_feed > /dev/null; then
            local rss_prefill_post_data=""
            local rss_prefill_slug rss_template_entry
            for rss_prefill_slug in "${rss_prefill_slugs[@]}"; do
                rss_template_entry="${BSSG_RAM_RSS_TEMPLATE_BY_SLUG[$rss_prefill_slug]}"
                [ -z "$rss_template_entry" ] && continue
                rss_prefill_post_data+="${rss_template_entry//%TAG%/__prefill__}"$'\n'
            done
            if [ -n "$rss_prefill_post_data" ]; then
                if [ "${RAM_MODE_VERBOSE:-false}" = true ]; then
                    local max_posts_label="unlimited"
                    if [ "$rss_prefill_max_posts" -gt 0 ]; then
                        max_posts_label="$rss_prefill_max_posts"
                    fi
                    echo -e "DEBUG: Pre-warming RAM RSS item cache for ${#rss_prefill_slugs[@]} posts (${rss_prefill_occurrences} tag-RSS slots, min hits: ${rss_prefill_min_hits}, max posts: ${max_posts_label}, pool: ${rss_prefill_pool_count})."
                fi
                _generate_rss_feed "/dev/null" "__prefill__" "__prefill__" "/" "/rss.xml" "$rss_prefill_post_data" >/dev/null || true
            fi
        fi
    fi

    if [ "$ram_tags_timing_enabled" = true ]; then
        local now_ms
        now_ms="$(_bssg_tags_now_ms)"
        tags_prep_ms=$((now_ms - tags_phase_start_ms))
        tags_phase_start_ms="$now_ms"
    fi

    local tag_url
    local cores
    cores=$(get_parallel_jobs)
    if [ "$cores" -gt "$tag_count" ]; then
        cores="$tag_count"
    fi

    if [ "$tag_count" -gt 1 ] && [ "$cores" -gt 1 ]; then
        local worker_pids=()
        local worker_idx
        for ((worker_idx = 0; worker_idx < cores; worker_idx++)); do
            (
                local idx local_tag_url local_tag
                for ((idx = worker_idx; idx < tag_count; idx += cores)); do
                    local_tag_url="${sorted_tag_urls[$idx]}"
                    local_tag="${tag_name_by_slug[$local_tag_url]}"
                    _process_single_tag_page_ram "$local_tag_url" "$local_tag"
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
            echo -e "${RED}Parallel RAM-mode tag processing failed.${NC}"
            exit 1
        fi
    else
        for tag_url in "${sorted_tag_urls[@]}"; do
            tag="${tag_name_by_slug[$tag_url]}"
            _process_single_tag_page_ram "$tag_url" "$tag"
        done
    fi

    if [ "$ram_tags_timing_enabled" = true ]; then
        local now_ms
        now_ms="$(_bssg_tags_now_ms)"
        tags_render_ms=$((now_ms - tags_phase_start_ms))
        tags_phase_start_ms="$now_ms"
    fi

    local header_content="$HEADER_TEMPLATE"
    local footer_content="$FOOTER_TEMPLATE"
    header_content=${header_content//\{\{site_title\}\}/"$SITE_TITLE"}
    header_content=${header_content//\{\{page_title\}\}/"${MSG_ALL_TAGS:-"All Tags"}"}
    header_content=${header_content//\{\{site_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{twitter_description\}\}/"$SITE_DESCRIPTION"}
    header_content=${header_content//\{\{og_type\}\}/"website"}
    header_content=${header_content//\{\{page_url\}\}/"/tags/"}
    header_content=${header_content//\{\{site_url\}\}/"$SITE_URL"}
    header_content=${header_content//<!-- bssg:tag_rss_link -->/}
    local tags_schema_json
    tags_schema_json=$(cat <<EOF
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "name": "${MSG_ALL_TAGS:-"All Tags"}",
  "description": "List of all tags on $SITE_TITLE",
  "url": "$SITE_URL/tags/",
  "isPartOf": {
    "@type": "WebSite",
    "name": "$SITE_TITLE",
    "url": "$SITE_URL"
  }
}
</script>
EOF
)
    header_content=${header_content//\{\{schema_json_ld\}\}/"$tags_schema_json"}
    header_content=${header_content//\{\{og_image\}\}/""}
    header_content=${header_content//\{\{twitter_image\}\}/""}
    footer_content=${footer_content//\{\{current_year\}\}/$(date +%Y)}
    footer_content=${footer_content//\{\{author_name\}\}/"$AUTHOR_NAME"}

    exec 5> "$main_tags_index_output"
    printf '%s\n' "$header_content" >&5
    printf '<h1>%s</h1>\n' "${MSG_ALL_TAGS:-All Tags}" >&5
    printf '<div class="tags-list">\n' >&5
    for tag_url in "${sorted_tag_urls[@]}"; do
        tag="${tag_name_by_slug[$tag_url]}"
        local post_count="${BSSG_RAM_TAG_POST_COUNT_BY_SLUG[$tag_url]:-0}"
        printf '    <a href="%s/tags/%s/">%s <span class="tag-count">(%s)</span></a>\n' "$SITE_URL" "$tag_url" "$tag" "$post_count" >&5
    done
    printf '</div>\n' >&5
    printf '%s\n' "$footer_content" >&5
    exec 5>&-

    if [ "$ram_tags_timing_enabled" = true ]; then
        local now_ms
        now_ms="$(_bssg_tags_now_ms)"
        tags_index_ms=$((now_ms - tags_phase_start_ms))
        tags_total_ms=$((now_ms - tags_total_start_ms))
        echo -e "${BLUE}RAM tags sub-timing:${NC}"
        echo -e "  Prepare maps/cache: $(_bssg_tags_format_ms "$tags_prep_ms")"
        echo -e "  Tag pages+RSS:      $(_bssg_tags_format_ms "$tags_render_ms")"
        echo -e "  tags/index.html:    $(_bssg_tags_format_ms "$tags_index_ms")"
        echo -e "  Total tags stage:   $(_bssg_tags_format_ms "$tags_total_ms")"
    fi

    BSSG_RAM_TAG_POST_SLUGS_BY_SLUG=()
    BSSG_RAM_TAG_POST_COUNT_BY_SLUG=()
    BSSG_RAM_TAG_ARTICLE_HTML_BY_SLUG=()
    BSSG_RAM_RSS_TEMPLATE_BY_SLUG=()
    BSSG_RAM_TAG_HEADER_BASE=""
    BSSG_RAM_TAG_FOOTER_CONTENT=""
    BSSG_RAM_TAG_DISPLAY_DATE_FORMAT=""

    echo -e "${GREEN}Tag pages processed!${NC}"
}

# Generate tag pages
generate_tag_pages() {
    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        _generate_tag_pages_ram
        return $?
    fi

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

                        local _ _ title date lastmod filename slug image image_caption description author_name author_email
                        IFS='|' read -r _ _ title date lastmod filename slug image image_caption description author_name author_email <<< "$post_line"

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

                        # Determine author for display (with fallback)
                        local display_author_name="${author_name:-${AUTHOR_NAME:-Anonymous}}"

                        # --- Start Debug: Check variables before appending article ---
                        #echo "DEBUGAPPEND (tag='$tag', title='$title'): Appending article HTML with link='$post_link', date='$formatted_date'" >&2
                        # --- End Debug ---

                        cat >> "$tag_page_html_file" << EOF
    <article>
        <h3><a href="${SITE_URL}${post_link}">$title</a></h3>
        <div class="meta">${MSG_PUBLISHED_ON:-"Published on"} $formatted_date ${MSG_BY:-"by"} <strong>$display_author_name</strong></div>
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
                # IMPORTANT: tags_index.txt has format: Tag|TagSlug|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|Image|ImageCaption|PostDescription|AuthorName|AuthorEmail
                # We need to map this to the format expected by _generate_rss_feed:
                # file|filename|title|date|lastmod|tags|slug|image|image_caption|description|author_name|author_email
                # We lack the original 'file' path and 'tags' string here. We can approximate.

                local tag_post_data_tmp=$(mktemp)
                # Read from pre-grouped file, sort, limit, and map fields using awk
                sort -t'|' -k4,4r -k5,5r "$tag_specific_data_file" | \
                head -n "$rss_item_limit" | \
                awk -F'|' -v tag_val="$tag" 'BEGIN {OFS="|"} {
                    # Reconstruct needed fields. Use filename ($6) as placeholder for first field.
                    # file (placeholder) | filename | title | date | lastmod | tags | slug | image | image_caption | description | author_name | author_email
                    print $6 "|" $6 "|" $3 "|" $4 "|" $5 "|" tag_val "|" $7 "|" $8 "|" $9 "|" $10 "|" $11 "|" $12
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
            local cores
            cores=$(get_parallel_jobs)
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
