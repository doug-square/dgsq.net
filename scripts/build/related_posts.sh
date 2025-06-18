#!/usr/bin/env bash
#
# BSSG - Related Posts Module
# Functions for generating related posts based on shared tags
#

# Source dependencies
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from related_posts.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from related_posts.sh"; exit 1; }

# --- Related Posts Functions --- START ---

# Generate related posts for a given post based on shared tags
# Args: $1=current_post_slug $2=current_post_tags $3=current_post_date $4=max_results (optional, default=3)
# Returns: HTML snippet with related posts
generate_related_posts() {
    local current_slug="$1"
    local current_tags="$2"
    local current_date="$3"
    local max_results="${4:-3}"
    
    # Validate inputs
    if [[ -z "$current_slug" || -z "$current_tags" ]]; then
        return 0  # No related posts if missing essential data
    fi
    
    # Check cache first
    local cache_file="${CACHE_DIR:-.bssg_cache}/related_posts/${current_slug}.html"
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    
    # Create cache directory if it doesn't exist
    mkdir -p "$(dirname "$cache_file")"
    
    # Check if cache is valid (newer than file index)
    if [[ -f "$cache_file" && -f "$file_index" ]]; then
        if [[ "$cache_file" -nt "$file_index" ]] && [[ "${FORCE_REBUILD:-false}" != true ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Generate related posts
    local related_posts_html=""
    related_posts_html=$(compute_related_posts "$current_slug" "$current_tags" "$current_date" "$max_results")
    
    # Cache the result
    echo "$related_posts_html" > "$cache_file"
    
    # Output the result
    echo "$related_posts_html"
}

# Core algorithm to compute related posts
compute_related_posts() {
    local current_slug="$1"
    local current_tags="$2" 
    local current_date="$3"
    local max_results="$4"
    
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    
    if [[ ! -f "$file_index" ]]; then
        return 0  # No posts to compare against
    fi
    
    # Convert current tags to array for comparison
    IFS=',' read -ra current_tags_array <<< "$current_tags"
    local current_tags_clean=()
    for tag in "${current_tags_array[@]}"; do
        tag=$(echo "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')  # Trim whitespace
        if [[ -n "$tag" ]]; then
            current_tags_clean+=("$tag")
        fi
    done
    
    # If no valid tags, return empty
    if [[ ${#current_tags_clean[@]} -eq 0 ]]; then
        return 0
    fi
    
    # Process all posts and calculate similarity scores
    local temp_results=$(mktemp)
    
    while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
        # Skip current post
        if [[ "$slug" == "$current_slug" ]]; then
            continue
        fi
        
        # Skip posts without tags or date
        if [[ -z "$tags" || -z "$date" ]]; then
            continue
        fi
        
        # Calculate similarity score based on shared tags
        local score=0
        IFS=',' read -ra post_tags_array <<< "$tags"
        
        for post_tag in "${post_tags_array[@]}"; do
            post_tag=$(echo "$post_tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')  # Trim whitespace
            if [[ -n "$post_tag" ]]; then
                for current_tag in "${current_tags_clean[@]}"; do
                    if [[ "$post_tag" == "$current_tag" ]]; then
                        score=$((score + 1))
                        break
                    fi
                done
            fi
        done
        
        # Only consider posts with at least one shared tag
        if [[ $score -gt 0 ]]; then
            # Store: score|date|title|slug|description
            echo "${score}|${date}|${title}|${slug}|${description}" >> "$temp_results"
        fi
        
    done < "$file_index"
    
    # Sort by score (descending), then by date (descending), limit results
    local sorted_results=""
    if [[ -s "$temp_results" ]]; then
        sorted_results=$(sort -t'|' -k1,1nr -k2,2r "$temp_results" | head -n "$max_results")
    fi
    rm -f "$temp_results"
    
    # Generate HTML output
    if [[ -z "$sorted_results" ]]; then
        return 0  # No related posts found
    fi
    
    local html_output=""
    html_output+='<section class="related-posts">'$'\n'
    html_output+='<h3>'"${MSG_RELATED_POSTS:-Related Posts}"'</h3>'$'\n'
    html_output+='<div class="related-posts-list">'$'\n'
    
    while IFS='|' read -r score date title slug description; do
        if [[ -n "$slug" && -n "$title" ]]; then
            # Generate post URL using the same logic as the main post generation
            local post_year post_month post_day
            if [[ "$date" =~ ^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2}) ]]; then
                post_year="${BASH_REMATCH[1]}"
                post_month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
                post_day=$(printf "%02d" "$((10#${BASH_REMATCH[3]}))")
            else
                post_year=$(date +%Y); post_month=$(date +%m); post_day=$(date +%d)
            fi
            
            local url_path="${URL_SLUG_FORMAT:-Year/Month/Day/slug}"
            url_path="${url_path//Year/$post_year}"
            url_path="${url_path//Month/$post_month}"
            url_path="${url_path//Day/$post_day}"
            url_path="${url_path//slug/$slug}"
            local post_url="/${url_path}/"
            
            # Truncate description if too long
            local short_desc="$description"
            if [[ ${#short_desc} -gt 120 ]]; then
                short_desc="${short_desc:0:117}..."
            fi
            
            html_output+='<article class="related-post">'$'\n'
            html_output+='<h4><a href="'"${SITE_URL:-}${post_url}"'">'"$title"'</a></h4>'$'\n'
            if [[ -n "$short_desc" ]]; then
                html_output+='<p>'"$short_desc"'</p>'$'\n'
            fi
            html_output+='</article>'$'\n'
        fi
    done <<< "$sorted_results"
    
    html_output+='</div>'$'\n'
    html_output+='</section>'$'\n'
    
    echo "$html_output"
}

# Clean related posts cache (called when posts are modified)
clean_related_posts_cache() {
    local cache_dir="${CACHE_DIR:-.bssg_cache}/related_posts"
    if [[ -d "$cache_dir" ]]; then
        echo -e "${YELLOW}Cleaning related posts cache...${NC}"
        rm -rf "$cache_dir"
        mkdir -p "$cache_dir"
    fi
}

# Invalidate related posts cache for posts that share tags with modified posts
# Args: $1=path to modified tags list file, $2=optional output file for invalidated post slugs
invalidate_related_posts_cache_for_tags() {
    local modified_tags_file="$1"
    local invalidated_output_file="$2"
    local cache_dir="${CACHE_DIR:-.bssg_cache}/related_posts"
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    
    if [[ ! -f "$modified_tags_file" || ! -d "$cache_dir" || ! -f "$file_index" ]]; then
        return 0
    fi
    
    # Read modified tags into array
    local modified_tags=()
    while IFS= read -r tag; do
        if [[ -n "$tag" ]]; then
            modified_tags+=("$tag")
        fi
    done < "$modified_tags_file"
    
    if [[ ${#modified_tags[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Invalidating related posts cache for posts with modified tags...${NC}"
    
    # Find posts that have any of the modified tags and remove their cache
    while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email; do
        if [[ -n "$tags" && -n "$slug" ]]; then
            IFS=',' read -ra post_tags_array <<< "$tags"
            local should_invalidate=false
            
            for post_tag in "${post_tags_array[@]}"; do
                post_tag=$(echo "$post_tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -n "$post_tag" ]]; then
                    for modified_tag in "${modified_tags[@]}"; do
                        if [[ "$post_tag" == "$modified_tag" ]]; then
                            should_invalidate=true
                            break 2
                        fi
                    done
                fi
            done
            
            if [[ "$should_invalidate" == true ]]; then
                local cache_file="$cache_dir/${slug}.html"
                if [[ -f "$cache_file" ]]; then
                    rm -f "$cache_file"
                    echo -e "  Invalidated cache for post: ${GREEN}$slug${NC}"
                fi
                
                # Write the slug to the output file if provided
                if [[ -n "$invalidated_output_file" ]]; then
                    echo "$slug" >> "$invalidated_output_file"
                fi
            fi
        fi
    done < "$file_index"
}

# --- Related Posts Functions --- END ---

# Export functions for use by other scripts
export -f generate_related_posts compute_related_posts clean_related_posts_cache invalidate_related_posts_cache_for_tags 