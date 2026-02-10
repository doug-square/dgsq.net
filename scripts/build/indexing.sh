#!/usr/bin/env bash
#
# BSSG - Indexing Utilities
# Functions for building intermediate file, tag, and archive indexes.
#

# Source Utilities and Content functions needed by indexing functions
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from indexing.sh"; exit 1; }
# shellcheck source=content.sh disable=SC1091
source "$(dirname "$0")/content.sh" || { echo >&2 "Error: Failed to source content.sh from indexing.sh"; exit 1; }
# shellcheck source=cache.sh disable=SC1091 # Needed for indexes_need_rebuild
source "$(dirname "$0")/cache.sh" || { echo >&2 "Error: Failed to source cache.sh from indexing.sh"; exit 1; }

# Global arrays (consider moving to main context if feasible)
declare -A file_index_data

# --- Indexing Functions --- START ---

# Step 1: Build a raw index using centralized awk (fast extraction only)
_build_raw_file_index() {
    local all_files_list="$1" # Input: file containing list of source files
    local output_raw_index="$2" # Output: path for the raw index file

    # Awk script to parse frontmatter - only extracts found fields
    # No fallbacks handled here. Output includes filename and basename.
    awk -f - $(<"$all_files_list") <<'EOF' > "$output_raw_index"
    BEGIN { 
        FS="|"; OFS="|"; 
    }
    function reset_vars() {
        vars["title"] = ""; vars["date"] = ""; vars["lastmod"] = "";
        vars["tags"] = ""; vars["slug"] = ""; vars["image"] = "";
        vars["image_caption"] = ""; vars["description"] = "";
        vars["author_name"] = ""; vars["author_email"] = "";
        in_fm = 0; found_fm = 0;
        is_html = (FILENAME ~ /\.html$/);
        is_md = (FILENAME ~ /\.md$/);
    }
    FNR == 1 { 
        if (NR > 1) {
             # Print previous file raw data
             print current_filename, current_basename, vars["title"], vars["date"], vars["lastmod"], \
                   vars["tags"], vars["slug"], vars["image"], vars["image_caption"], vars["description"], \
                   vars["author_name"], vars["author_email"];
        }
        reset_vars();
        current_filename = FILENAME;
        current_basename = FILENAME;
        sub(/.*\//, "", current_basename); # Get basename
    }
    # Markdown Parsing
    is_md && /^---$/ {
        if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
        if (in_fm) { in_fm = 0; next; }
    }
    is_md && in_fm {
        # Use compatible match for key-value extraction
        if (match($0, /^([^:]+):[[:space:]]*(.*[^[:space:]])[[:space:]]*$/)) {
            full_match = substr($0, RSTART, RLENGTH)
            # Extract key part
            key_start = match(full_match, /^[^:]+/)
            key_str = substr(full_match, RSTART, RLENGTH)
            # Extract value part (handle potential quotes)
            value_start = match(full_match, /:[[:space:]]*(.*)$/)
            value = substr(full_match, RSTART + 1, RLENGTH - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key_str);
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value);
            key = tolower(key_str);
            # Remove surrounding quotes from value if present
            if ( (match(value, /^"(.*)"$/) || match(value, /^\'(.*)\'$/)) && length(value) > 1 ) {
                value = substr(value, 2, length(value)-2);
            }
            if (key in vars) { vars[key] = value; }
        }
        next; 
    }
    # HTML Parsing
    is_html && match($0, /<title>([^<]*)<\/title>/) { 
        # Extract content within <title> tags
        title_content = substr($0, RSTART + 7, RLENGTH - 15)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", title_content); # Trim whitespace
        # Only set title if it wasn't already set by frontmatter (e.g., in markdown)
        if (vars["title"] == "") {
           vars["title"] = title_content; 
        }
    }
    is_html && match($0, /<meta[^>]+name="([^"]+)"[^>]+content="([^"]*)"[^>]*>/) {
        # Extract key (name attribute)
        key_match_start = RSTART + index($0, "name=") + 5 # Position after name="
        key_match_len = index(substr($0, key_match_start), "\"") -1
        key = tolower(substr($0, key_match_start, key_match_len));
        
        # Extract value (content attribute)
        content_match_start = RSTART + index($0, "content=") + 8 # Position after content="
        content_match_len = index(substr($0, content_match_start), "\"") -1
        value = substr($0, content_match_start, content_match_len);

        # Only set if the key is one we care about and not already set
        if (key in vars && vars[key] == "") { vars[key] = value; }
    }
    END {
        if (NR > 0) {
             # Print last file raw data
             print current_filename, current_basename, vars["title"], vars["date"], vars["lastmod"], \
                   vars["tags"], vars["slug"], vars["image"], vars["image_caption"], vars["description"], \
                   vars["author_name"], vars["author_email"];
        }
    }
EOF
}

# Step 2: Process the raw index, applying fallbacks for missing essential fields
_process_raw_file_index() {
    local input_raw_index="$1" # Input: path to the raw index file
    local output_processed_index="$2" # Output: path for the final processed index

    # Export functions needed in the loop
    export -f get_file_mtime format_date_from_timestamp generate_slug generate_excerpt
    export DATE_FORMAT # Needed by format_date_from_timestamp
    export SRC_DIR # Needed indirectly by generate_excerpt if path is relative?

    > "$output_processed_index" # Ensure output file is empty

    local file filename title date lastmod tags slug image image_caption description author_name author_email
    local file_mtime
    while IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email || [[ -n "$file" ]]; do
        # Fallback for Title (use filename without extension)
        if [ -z "$title" ]; then
            title="${filename%.*}"
        fi
        
        # Fallback for Date (use file modification time)
        if [ -z "$date" ]; then
            file_mtime=$(get_file_mtime "$file")
            date=$(format_date_from_timestamp "$file_mtime")
        fi

        # Fallback for Last Modified Date (use date if lastmod is missing)
        if [ -z "$lastmod" ]; then
            lastmod="$date"
        fi

        if [ -n "$slug" ]; then
            # Ensure slug is sanitized
            slug=$(generate_slug "$slug")
        fi
        # Fallback for Slug (generate from title)
        if [ -z "$slug" ]; then
            # Ensure title is available for slug generation
            if [ -z "$title" ]; then title="${filename%.*}"; fi
            slug=$(generate_slug "$title")
        fi

        # Fallback for Description (generate excerpt)
        # Check if description is empty or contains only whitespace
        if [[ -z "$description" || "$description" =~ ^[[:space:]]*$ ]]; then
            description=$(generate_excerpt "$file")
        fi
        
        # Apply fallback logic for author fields
        if [ -z "$author_name" ]; then
            author_name="${AUTHOR_NAME:-Anonymous}"
        fi
        if [ -z "$author_email" ] && [ -n "$author_name" ] && [ "$author_name" = "${AUTHOR_NAME:-Anonymous}" ]; then
            # Only use default email if using default name
            author_email="${AUTHOR_EMAIL:-}"
        fi
        # If author_name is specified but author_email is empty, leave email empty
        
        # Output the fully processed line to the final index file
        echo "$file|$filename|$title|$date|$lastmod|$tags|$slug|$image|$image_caption|$description|$author_name|$author_email" >> "$output_processed_index"
    done < "$input_raw_index"
    wait # Ensure background processes from potential subshells (like generate_excerpt) finish
}

# Optimized file index building - orchestrates raw build and processing
_build_file_index_from_ram() {
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local metadata
        metadata=$(extract_metadata "$file") || continue
        local filename
        filename=$(basename "$file")
        echo "$file|$filename|$metadata"
    done < <(ram_mode_list_src_files) | sort -t '|' -k 4,4r -k 1,1
}

optimized_build_file_index() {
    echo -e "${YELLOW}Building file index...${NC}"
    
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local index_marker="${CACHE_DIR:-.bssg_cache}/index_marker"
    local frontmatter_changes_marker="${CACHE_DIR:-.bssg_cache}/frontmatter_changes_marker"

    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_list_src_files > /dev/null; then
        local file_index_data
        file_index_data=$(_build_file_index_from_ram)
        ram_mode_set_dataset "file_index" "$file_index_data"
        ram_mode_clear_dataset "file_index_prev"
        ram_mode_set_dataset "frontmatter_changes_marker" "1"
        echo -e "${GREEN}File index built from RAM preload with $(ram_mode_dataset_line_count "file_index") complete entries!${NC}"
        return 0
    fi
    
    # Check if rebuild is needed
    if [ "${FORCE_REBUILD:-false}" = false ] && [ -f "$file_index" ] && [ -f "$index_marker" ]; then
        local newest_file_time=0
        # Use find -printf for efficiency if available (GNU find)
        if find --version >/dev/null 2>&1 && grep -q GNU <<< "$(find --version)"; then
             newest_file_time=$(find "${SRC_DIR:-src}" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" -printf '%T@\n' 2>/dev/null | sort -nr | head -n 1)
             newest_file_time=${newest_file_time:-0} # Handle empty dir
             newest_file_time=${newest_file_time%.*} # Truncate to integer
        else # POSIX/BSD find
            local src_files
            # Use -exec stat for better portability than parsing ls
            # This might still be slow on very large sites compared to GNU find -printf
            newest_file_time=$(find "${SRC_DIR:-src}" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" -exec stat -f %m {} \; 2>/dev/null | sort -nr | head -n 1)
            newest_file_time=${newest_file_time:-0} # Handle empty dir
        fi
        
        local marker_time=$(get_file_mtime "$index_marker")
        # Defensive check: if marker_time is 0 or invalid, force rebuild
        [[ -z "$marker_time" || "$marker_time" -eq 0 ]] && marker_time=0 

        # Check if any source file is newer than the marker
        if [[ "$newest_file_time" -gt 0 && "$marker_time" -gt 0 && "$newest_file_time" -le "$marker_time" ]]; then
            echo -e "${GREEN}File index is up to date, skipping...${NC}"
            return 0
        else
            echo -e "${YELLOW}File index rebuild needed (newest file: $newest_file_time, marker: $marker_time).${NC}"
        fi
    fi
    
    lock_file "$file_index"
    
    # Find all markdown/html files
    local all_files_list="${CACHE_DIR:-.bssg_cache}/all_files_list.$$"
    find "${SRC_DIR:-src}" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" | sort > "$all_files_list"
    trap 'rm -f "$all_files_list"' EXIT # Ensure cleanup
    
    local total_files=$(wc -l < "$all_files_list")
    if [ "$total_files" -eq 0 ]; then
        echo -e "${YELLOW}No source files found in ${SRC_DIR:-src}. Skipping index build.${NC}"
        > "$file_index" # Create empty index
        touch "$index_marker"
        unlock_file "$file_index"
        rm -f "$all_files_list"
        trap - EXIT # Remove trap
        return 0
    fi
    echo "Found $total_files files in source directory."

    # Define temporary file paths
    local file_index_raw="${CACHE_DIR:-.bssg_cache}/file_index.raw.$$"
    local file_index_processed="${CACHE_DIR:-.bssg_cache}/file_index.processed.$$"
    local file_index_sorted="${CACHE_DIR:-.bssg_cache}/file_index.sorted.$$"
    trap 'rm -f "$all_files_list" "$file_index_raw" "$file_index_processed" "$file_index_sorted"' EXIT # Ensure cleanup

    # Step 1: Build raw index (fast awk extraction)
    echo "Step 1: Processing $total_files files using centralized awk for raw data..."
    _build_raw_file_index "$all_files_list" "$file_index_raw"
    rm -f "$all_files_list" # Clean up file list immediately after use

    # Step 2: Process raw index (apply fallbacks)
    echo "Step 2: Applying fallbacks for missing fields..."
    _process_raw_file_index "$file_index_raw" "$file_index_processed"
    rm -f "$file_index_raw"

    # Step 3: Sort the final processed index by date (field 4) reverse chronologically
    echo "Step 3: Sorting processed index..."
    sort -t '|' -k 4,4r -k 1,1 "$file_index_processed" > "$file_index_sorted" # Add secondary sort by filename
    rm -f "$file_index_processed"

    # Check if file_index content has changed
    local index_content_changed=false
    if [ -f "$file_index" ]; then
        # Check if the file content differs using cmp (portable)
        if ! cmp -s "$file_index_sorted" "$file_index"; then
            # cmp exits 1 if files differ, 0 if same
            index_content_changed=true
            echo -e "${YELLOW}File index has changed.${NC}" >&2
        fi
    else
        index_content_changed=true # No previous index exists
    fi

    # Move sorted index to final location if content changed
    if [ "$index_content_changed" = true ]; then
        echo -e "${YELLOW}Updating file index.${NC}" >&2
        mv "$file_index_sorted" "$file_index"
        # Update frontmatter changes marker if content changed
        touch "$frontmatter_changes_marker"
        echo -e "${YELLOW}File index changed, updating frontmatter marker.${NC}" >&2
        # Update the main index marker timestamp
        touch "$index_marker"
    else
        echo -e "${GREEN}File index content unchanged, discarding sorted version.${NC}" >&2
        rm -f "$file_index_sorted"
        # Keep the old marker timestamp
    fi

    unlock_file "$file_index"
    trap - EXIT # Remove trap upon successful completion
    
    echo -e "${GREEN}File index built with $(wc -l < "$file_index") complete entries!${NC}"
}

# Build tags index from the file index
build_tags_index() {
    echo -e "${YELLOW}Building tags index...${NC}"

    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local tags_index_file="${CACHE_DIR:-.bssg_cache}/tags_index.txt"
    local frontmatter_changes_marker="${CACHE_DIR:-.bssg_cache}/frontmatter_changes_marker"

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local file_index_data tags_index_data
        file_index_data=$(ram_mode_get_dataset "file_index")
        if [ -z "$file_index_data" ]; then
            ram_mode_set_dataset "tags_index" ""
            ram_mode_clear_dataset "has_tags"
            echo -e "${GREEN}Tags index built!${NC}"
            return 0
        fi

        tags_index_data=$(printf '%s\n' "$file_index_data" | awk -F'|' -v OFS='|' '
            {
                if (length($6) > 0) {
                    split($6, tags_array, ",");
                    for (i in tags_array) {
                        tag = tags_array[i];
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", tag);
                        if (length(tag) == 0) continue;

                        tag_slug = tolower(tag);
                        gsub(/[^a-z0-9]+/, "-", tag_slug);
                        gsub(/^-+|-+$/, "", tag_slug);
                        if (length(tag_slug) == 0) tag_slug = "-";

                        print tag, tag_slug, $3, $4, $5, $2, $7, $8, $9, $10, $11, $12;
                    }
                }
            }')
        ram_mode_set_dataset "tags_index" "$tags_index_data"
        if [ -n "$tags_index_data" ]; then
            ram_mode_set_dataset "has_tags" "1"
        else
            ram_mode_clear_dataset "has_tags"
        fi
        echo -e "${GREEN}Tags index built!${NC}"
        return 0
    fi

    # --- Optimized Rebuild Check --- START ---
    local rebuild_needed=false
    local reason=""

    # 1. Check if tags index file exists
    if [ ! -f "$tags_index_file" ]; then
        rebuild_needed=true
        reason="Tags index file does not exist."
    # 2. Check for global config changes (using exported status)
    elif [ "${BSSG_CONFIG_CHANGED_STATUS:-1}" -eq 0 ]; then
        rebuild_needed=true
        reason="Global configuration changed."
    # 3. Check if file index (list of posts) is newer
    elif [ "$file_index" -nt "$tags_index_file" ]; then
        rebuild_needed=true
        reason="File index is newer than tags index."
    # 4. Check if frontmatter of any post has changed
    elif [ -f "$frontmatter_changes_marker" ] && [ "$frontmatter_changes_marker" -nt "$tags_index_file" ]; then
        rebuild_needed=true
        reason="Post frontmatter changed."
    fi

    if ! $rebuild_needed; then
        echo -e "${GREEN}Tags index is up to date, skipping...${NC}"
        return 0
    else
        echo -e "${YELLOW}Rebuilding tags index: $reason${NC}"
    fi
    # --- Optimized Rebuild Check --- END ---

    if [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index '$file_index' not found. Cannot build tags index.${NC}"
        return 1
    fi

    lock_file "$tags_index_file"
    
    # > "$tags_index_file"  # Clear the file - AWK will overwrite

    # Read from file index and extract tags
    # Use awk for efficient processing and slug generation
    awk -F'|' -v OFS='|' '{
        # $1=file, $2=filename, $3=title, $4=date, $5=lastmod, 
        # $6=tags, $7=slug, $8=image, $9=image_caption, $10=description, $11=author_name, $12=author_email
        if (length($6) > 0) { # Check if tags field is not empty
            split($6, tags_array, ","); # Split tags by comma
            for (i in tags_array) {
                tag = tags_array[i];
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", tag); # Trim whitespace
                if (length(tag) == 0) continue; # Skip empty tags

                # Generate slug within awk (replicating generate_slug logic)
                tag_slug = tolower(tag);
                gsub(/[^a-z0-9]+/, "-", tag_slug); # Replace non-alphanumeric with hyphens
                gsub(/^-+|-+$/, "", tag_slug); # Trim leading/trailing hyphens
                if (length(tag_slug) == 0) tag_slug = "-"; # Handle empty slugs
                
                # Print: TagName|TagSlug|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|PostImage|PostImageCaption|PostDescription|AuthorName|AuthorEmail
                print tag, tag_slug, $3, $4, $5, $2, $7, $8, $9, $10, $11, $12;
            }
        }
    }' "$file_index" > "$tags_index_file" 
    
    unlock_file "$tags_index_file"

    # Check if the generated index is not empty and create/remove flag file
    local tags_flag_file="${CACHE_DIR:-.bssg_cache}/has_tags.flag"
    if [ -s "$tags_index_file" ]; then
        touch "$tags_flag_file"
    else
        rm -f "$tags_flag_file"
    fi

    echo -e "${GREEN}Tags index built!${NC}"
}

# Build authors index from the file index
build_authors_index() {
    echo -e "${YELLOW}Building authors index...${NC}"
    
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local authors_index_file="${CACHE_DIR:-.bssg_cache}/authors_index.txt"

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local file_index_data authors_index_data
        file_index_data=$(ram_mode_get_dataset "file_index")
        if [ -z "$file_index_data" ]; then
            ram_mode_set_dataset "authors_index" ""
            ram_mode_clear_dataset "has_authors"
            echo -e "${GREEN}Authors index built!${NC}"
            return 0
        fi

        authors_index_data=$(printf '%s\n' "$file_index_data" | awk -F'|' -v OFS='|' '
            {
                author_name = $11;
                author_email = $12;
                if (length(author_name) == 0) next;

                author_slug = tolower(author_name);
                gsub(/[^a-z0-9]+/, "-", author_slug);
                gsub(/^-+|-+$/, "", author_slug);
                if (length(author_slug) == 0) author_slug = "anonymous";

                print author_name, author_slug, author_email, $3, $4, $5, $2, $7, $8, $9, $10;
            }')
        ram_mode_set_dataset "authors_index" "$authors_index_data"
        if [ -n "$authors_index_data" ]; then
            ram_mode_set_dataset "has_authors" "1"
        else
            ram_mode_clear_dataset "has_authors"
        fi
        echo -e "${GREEN}Authors index built!${NC}"
        return 0
    fi

    # Check if rebuild is needed: missing cache or input/dependencies changed
    local rebuild_needed=false
    if [ ! -f "$authors_index_file" ]; then
        rebuild_needed=true
    elif file_needs_rebuild "$file_index" "$authors_index_file"; then
        echo -e "${YELLOW}Authors index is outdated or dependencies changed, rebuilding authors...${NC}"
        rebuild_needed=true
    fi

    if [ "$rebuild_needed" = false ]; then
         echo -e "${GREEN}Authors index is up to date, skipping...${NC}"
         return 0
    fi

    if [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index '$file_index' not found. Cannot build authors index.${NC}"
        return 1
    fi
    
    lock_file "$authors_index_file"
    
    > "$authors_index_file"  # Clear the file

    # Read from file index and extract author info
    # Use awk for efficient processing and slug generation
    awk -F'|' -v OFS='|' '{
        # $1=file, $2=filename, $3=title, $4=date, $5=lastmod, 
        # $6=tags, $7=slug, $8=image, $9=image_caption, $10=description, $11=author_name, $12=author_email
        author_name = $11;
        author_email = $12;
        
        # Skip if author_name is empty
        if (length(author_name) == 0) next;
        
        # Generate slug within awk (replicating generate_slug logic)
        author_slug = tolower(author_name);
        gsub(/[^a-z0-9]+/, "-", author_slug); # Replace non-alphanumeric with hyphens
        gsub(/^-+|-+$/, "", author_slug); # Trim leading/trailing hyphens
        if (length(author_slug) == 0) author_slug = "anonymous"; # Handle empty slugs
        
        # Print: AuthorName|AuthorSlug|AuthorEmail|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|PostImage|PostImageCaption|PostDescription
        print author_name, author_slug, author_email, $3, $4, $5, $2, $7, $8, $9, $10;
    }' "$file_index" > "$authors_index_file" 
    
    unlock_file "$authors_index_file"

    # Check if the generated index is not empty and create/remove flag file
    local authors_flag_file="${CACHE_DIR:-.bssg_cache}/has_authors.flag"
    if [ -s "$authors_index_file" ]; then
        touch "$authors_flag_file"
    else
        rm -f "$authors_flag_file"
    fi

    echo -e "${GREEN}Authors index built!${NC}"
}

# Compare current and previous authors index to find affected authors and check if index needs rebuild
# Exports: AFFECTED_AUTHORS (space-separated list of author names)
#          AUTHORS_INDEX_NEEDS_REBUILD ("true" or "false")
identify_affected_authors() {
    local authors_index_file="${CACHE_DIR:-.bssg_cache}/authors_index.txt"
    local authors_index_prev_file="${CACHE_DIR:-.bssg_cache}/authors_index_prev.txt"

    export AFFECTED_AUTHORS=""
    export AUTHORS_INDEX_NEEDS_REBUILD="false"

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local authors_index_data
        authors_index_data=$(ram_mode_get_dataset "authors_index")
        if [ -n "$authors_index_data" ]; then
            AFFECTED_AUTHORS=$(printf '%s\n' "$authors_index_data" | awk -F'|' 'NF { print $1 }' | sort -u | tr '\n' ' ')
            AUTHORS_INDEX_NEEDS_REBUILD="true"
        fi
        export AFFECTED_AUTHORS
        export AUTHORS_INDEX_NEEDS_REBUILD
        return 0
    fi

    # If previous index doesn't exist, all authors in the current index are affected,
    # and the main index needs rebuilding.
    if [ ! -f "$authors_index_prev_file" ]; then
        if [ -s "$authors_index_file" ]; then # Check if current index has content
            echo "Previous authors index not found. Marking all authors as affected." >&2 # Debug
            AFFECTED_AUTHORS=$(cut -d'|' -f1 "$authors_index_file" | sort -u | tr '\n' ' ')
            AUTHORS_INDEX_NEEDS_REBUILD="true"
        else
             echo "Both previous and current authors indexes are missing or empty. No authors affected." >&2 # Debug
        fi
        export AFFECTED_AUTHORS
        export AUTHORS_INDEX_NEEDS_REBUILD
        return 0
    fi
    
    # If current index doesn't exist (but previous did), means all posts were deleted?
    # Mark authors from previous index as affected, index needs rebuild.
    if [ ! -f "$authors_index_file" ] || [ ! -s "$authors_index_file" ]; then
        echo "Current authors index not found or empty. Marking all previous authors as affected." >&2 # Debug
        AFFECTED_AUTHORS=$(cut -d'|' -f1 "$authors_index_prev_file" | sort -u | tr '\n' ' ')
        AUTHORS_INDEX_NEEDS_REBUILD="true"
        export AFFECTED_AUTHORS
        export AUTHORS_INDEX_NEEDS_REBUILD
        return 0
    fi

    # Extract AuthorName|Filename from both files for precise comparison
    local current_entries="${CACHE_DIR:-.bssg_cache}/authors_curr_af.$$"
    local prev_entries="${CACHE_DIR:-.bssg_cache}/authors_prev_af.$$"
    trap 'rm -f "$current_entries" "$prev_entries"' RETURN
    
    cut -d'|' -f1,7 "$authors_index_file" | sort > "$current_entries"
    cut -d'|' -f1,7 "$authors_index_prev_file" | sort > "$prev_entries"

    # Find differences (lines unique to current or previous)
    local diff_output
    diff_output=$(comm -3 "$current_entries" "$prev_entries")
    
    # Extract unique author names from the differences
    if [ -n "$diff_output" ]; then
        AFFECTED_AUTHORS=$(echo "$diff_output" | sed 's/^[[:space:]]*//' | cut -d'|' -f1 | sort -u | tr '\n' ' ')
        echo "Affected authors identified: $AFFECTED_AUTHORS" >&2 # Debug
    else
        echo "No difference in posts per author found." >&2 # Debug
        AFFECTED_AUTHORS=""
    fi

    # Compare author counts (AuthorName|Count) to see if the main index needs rebuilding
    local current_counts="${CACHE_DIR:-.bssg_cache}/authors_curr_counts.$$"
    local prev_counts="${CACHE_DIR:-.bssg_cache}/authors_prev_counts.$$"
    trap 'rm -f "$current_entries" "$prev_entries" "$current_counts" "$prev_counts"' RETURN

    cut -d'|' -f1 "$authors_index_file" | sort | uniq -c | awk '{print $2"|"$1}' | sort > "$current_counts"
    cut -d'|' -f1 "$authors_index_prev_file" | sort | uniq -c | awk '{print $2"|"$1}' | sort > "$prev_counts"
    
    if ! cmp -s "$current_counts" "$prev_counts"; then
        echo "Author counts differ. Main authors index needs rebuild." >&2 # Debug
        AUTHORS_INDEX_NEEDS_REBUILD="true"
    else
        echo "Author counts are the same." >&2 # Debug
        AUTHORS_INDEX_NEEDS_REBUILD="false"
    fi

    export AFFECTED_AUTHORS
    export AUTHORS_INDEX_NEEDS_REBUILD
    rm -f "$current_entries" "$prev_entries" "$current_counts" "$prev_counts"
    trap - RETURN # Remove trap upon successful completion
}

# Build archive index by year and month from the file index
build_archive_index() {
    echo -e "${YELLOW}Building archive index...${NC}"
    
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local archive_index_file="${CACHE_DIR:-.bssg_cache}/archive_index.txt"

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local file_index_data archive_index_data=""
        file_index_data=$(ram_mode_get_dataset "file_index")
        if [ -z "$file_index_data" ]; then
            ram_mode_set_dataset "archive_index" ""
            echo -e "${GREEN}Archive index built!${NC}"
            return 0
        fi

        local line file filename title date lastmod tags slug image image_caption description author_name author_email
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email <<< "$line"
            [ -z "$date" ] && continue

            local year month month_name
            if [[ "$date" =~ ^([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
            else
                continue
            fi

            local month_name_var="MSG_MONTH_${month}"
            month_name="${!month_name_var}"
            if [[ -z "$month_name" ]]; then
                month_name="$month"
            fi

            archive_index_data+="$year|$month|$month_name|$title|$date|$lastmod|$filename.html|$slug|$image|$image_caption|$description|$author_name|$author_email"$'\n'
        done <<< "$file_index_data"

        ram_mode_set_dataset "archive_index" "$archive_index_data"
        echo -e "${GREEN}Archive index built!${NC}"
        return 0
    fi

    # Check if rebuild is needed: missing cache or input/dependencies changed
    local rebuild_needed=false
    if [ ! -f "$archive_index_file" ]; then
        rebuild_needed=true
    elif file_needs_rebuild "$file_index" "$archive_index_file"; then
        echo -e "${YELLOW}Archive index is outdated or dependencies changed, rebuilding archives...${NC}"
        rebuild_needed=true
    fi

    if [ "$rebuild_needed" = false ]; then
         echo -e "${GREEN}Archive index is up to date, skipping...${NC}"
         return 0
    fi

    if [ ! -f "$file_index" ]; then
        echo -e "${RED}Error: File index '$file_index' not found. Cannot build archive index.${NC}"
        return 1
    fi
    
    lock_file "$archive_index_file"
    
    > "$archive_index_file"  # Clear the file

    # Read from file index and extract date info
    local line file filename title date lastmod tags slug image image_caption description author_name author_email
    while IFS= read -r line || [[ -n "$line" ]]; do
        IFS='|' read -r file filename title date lastmod tags slug image image_caption description author_name author_email <<< "$line"

        if [ -n "$date" ]; then
            local year month month_name
            # Extract year and month robustly
            if [[ "$date" =~ ^([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2}) ]]; then
                year="${BASH_REMATCH[1]}"
                # Force base-10 interpretation
                month=$(printf "%02d" "$((10#${BASH_REMATCH[2]}))")
            else
                # Attempt parsing with date command as fallback
                if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
                    year=$(date -j -f "%Y-%m-%d %H:%M:%S" "$date" "+%Y" 2>/dev/null || date -j -f "%Y-%m-%d" "$date" "+%Y" 2>/dev/null || echo "")
                    month=$(date -j -f "%Y-%m-%d %H:%M:%S" "$date" "+%m" 2>/dev/null || date -j -f "%Y-%m-%d" "$date" "+%m" 2>/dev/null || echo "")
                else # Linux
                    year=$(date -d "$date" "+%Y" 2>/dev/null || echo "")
                    month=$(date -d "$date" "+%m" 2>/dev/null || echo "")
                fi
            fi

            if [[ -z "$year" || -z "$month" ]]; then
                echo -e "${YELLOW}Warning: Could not parse date ('$date') in $file, skipping archive entry.${NC}" >&2
                continue
            fi

            # Get month name from locale messages if available, else default
            month_name_var="MSG_MONTH_${month}"
            month_name="${!month_name_var}"

            if [[ -z "$month_name" ]]; then # If locale lookup failed
                local input_date_for_month_name="${year}-${month}-01"
                if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *bsd* ]]; then
                     month_name=$(date -j -f "%Y-%m-%d" "$input_date_for_month_name" "+%B" 2>/dev/null)
                else
                     month_name=$(date -d "$input_date_for_month_name" "+%B" 2>/dev/null)
                fi
                [[ -z "$month_name" ]] && month_name="Unknown"
            fi

            # Output: Year|MonthNum|MonthName|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|PostImage|PostImageCaption|PostDescription|AuthorName|AuthorEmail
            echo "$year|$month|$month_name|$title|$date|$lastmod|$filename.html|$slug|$image|$image_caption|$description|$author_name|$author_email" >> "$archive_index_file"
        fi
    done < "$file_index"
    
    unlock_file "$archive_index_file"

    echo -e "${GREEN}Archive index built!${NC}"
}

# Compare current and previous archive index to find affected months and check if index needs rebuild
# Exports: AFFECTED_ARCHIVE_MONTHS (space-separated list of "YYYY|MM")
#          ARCHIVE_INDEX_NEEDS_REBUILD ("true" or "false")
identify_affected_archive_months() {
    local archive_index_file="${CACHE_DIR:-.bssg_cache}/archive_index.txt"
    local archive_index_prev_file="${CACHE_DIR:-.bssg_cache}/archive_index_prev.txt"

    export AFFECTED_ARCHIVE_MONTHS=""
    export ARCHIVE_INDEX_NEEDS_REBUILD="false"

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local archive_index_data
        archive_index_data=$(ram_mode_get_dataset "archive_index")
        if [ -n "$archive_index_data" ]; then
            AFFECTED_ARCHIVE_MONTHS=$(printf '%s\n' "$archive_index_data" | awk -F'|' 'NF { print $1 "|" $2 }' | sort -u | tr '\n' ' ')
            ARCHIVE_INDEX_NEEDS_REBUILD="true"
        fi
        export AFFECTED_ARCHIVE_MONTHS
        export ARCHIVE_INDEX_NEEDS_REBUILD
        return 0
    fi

    # If previous index doesn't exist, all months in the current index are affected,
    # and the main index needs rebuilding.
    if [ ! -f "$archive_index_prev_file" ]; then
        if [ -s "$archive_index_file" ]; then # Check if current index has content
            echo "Previous archive index not found. Marking all months as affected." >&2 # Debug
            AFFECTED_ARCHIVE_MONTHS=$(cut -d'|' -f1,2 "$archive_index_file" | sort -u | tr '\n' ' ')
            ARCHIVE_INDEX_NEEDS_REBUILD="true"
        else
             echo "Both previous and current archive indexes are missing or empty. No months affected." >&2 # Debug
        fi
        export AFFECTED_ARCHIVE_MONTHS
        export ARCHIVE_INDEX_NEEDS_REBUILD
        return 0
    fi
    
    # If current index doesn't exist (but previous did), means all posts were deleted?
    # Mark months from previous index as affected, index needs rebuild.
    if [ ! -f "$archive_index_file" ] || [ ! -s "$archive_index_file" ]; then
        echo "Current archive index not found or empty. Marking all previous months as affected." >&2 # Debug
        AFFECTED_ARCHIVE_MONTHS=$(cut -d'|' -f1,2 "$archive_index_prev_file" | sort -u | tr '\n' ' ')
        ARCHIVE_INDEX_NEEDS_REBUILD="true"
        export AFFECTED_ARCHIVE_MONTHS
        export ARCHIVE_INDEX_NEEDS_REBUILD
        return 0
    fi

    # Extract YYYY|MM|Filename from both files for precise comparison
    local current_entries="${CACHE_DIR:-.bssg_cache}/archive_curr_ymf.$$"
    local prev_entries="${CACHE_DIR:-.bssg_cache}/archive_prev_ymf.$$"
    trap 'rm -f "$current_entries" "$prev_entries"' RETURN
    
    cut -d'|' -f1,2,7 "$archive_index_file" | sort > "$current_entries"
    cut -d'|' -f1,2,7 "$archive_index_prev_file" | sort > "$prev_entries"

    # Find differences (lines unique to current or previous)
    local diff_output
    diff_output=$(comm -3 "$current_entries" "$prev_entries")
    
    # Extract unique YYYY|MM pairs from the differences
    if [ -n "$diff_output" ]; then
        AFFECTED_ARCHIVE_MONTHS=$(echo "$diff_output" | sed 's/^[[:space:]]*//' | cut -d'|' -f1,2 | sort -u | tr '\n' ' ')
        echo "Affected months identified: $AFFECTED_ARCHIVE_MONTHS" >&2 # Debug
    else
        echo "No difference in posts per month found." >&2 # Debug
        AFFECTED_ARCHIVE_MONTHS=""
    fi

    # Compare month counts (YYYY|MM|Count) to see if the main index needs rebuilding
    local current_counts="${CACHE_DIR:-.bssg_cache}/archive_curr_counts.$$"
    local prev_counts="${CACHE_DIR:-.bssg_cache}/archive_prev_counts.$$"
    trap 'rm -f "$current_entries" "$prev_entries" "$current_counts" "$prev_counts"' RETURN

    cut -d'|' -f1,2 "$archive_index_file" | sort | uniq -c | awk '{print $2"|"$1}' | sort > "$current_counts"
    cut -d'|' -f1,2 "$archive_index_prev_file" | sort | uniq -c | awk '{print $2"|"$1}' | sort > "$prev_counts"
    
    if ! cmp -s "$current_counts" "$prev_counts"; then
        echo "Month counts differ. Main archive index needs rebuild." >&2 # Debug
        ARCHIVE_INDEX_NEEDS_REBUILD="true"
    else
        echo "Month counts are the same." >&2 # Debug
        ARCHIVE_INDEX_NEEDS_REBUILD="false"
    fi

    export AFFECTED_ARCHIVE_MONTHS
    export ARCHIVE_INDEX_NEEDS_REBUILD
    rm -f "$current_entries" "$prev_entries" "$current_counts" "$prev_counts"
    trap - RETURN # Remove trap upon successful completion
}

# --- Indexing Functions --- END --- 
