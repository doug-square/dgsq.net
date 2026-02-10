#!/usr/bin/env bash
#
# BSSG - Content Processing Utilities
# Functions for parsing metadata, generating excerpts, and converting markdown.
#

# Source Utilities if needed by functions below
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from content.sh"; exit 1; }

# --- Content Functions --- START ---

# Parse metadata from a markdown file (uses cache)
parse_metadata() {
    local file="$1"
    local field="$2"
    local value=""

    # RAM mode: parse directly from preloaded content to avoid disk/cache I/O.
    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$file"; then
        local file_content frontmatter
        file_content=$(ram_mode_get_content "$file")
        frontmatter=$(printf '%s\n' "$file_content" | awk '
            BEGIN { in_fm = 0; found_fm = 0; }
            /^---$/ {
                if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
                if (in_fm) { exit; }
            }
            in_fm { print; }
        ')
        if [ -n "$frontmatter" ]; then
            value=$(printf '%s\n' "$frontmatter" | grep -m 1 "^$field:[[:space:]]*" | cut -d ':' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
        echo "$value"
        return 0
    fi

    # IMPORTANT: Assumes CACHE_DIR is exported/available
    local cache_file="${CACHE_DIR:-.bssg_cache}/meta/$(basename "$file")"

    # Get locks for cache access
    # IMPORTANT: Assumes lock_file/unlock_file are sourced/available
    lock_file "$cache_file"

    # Create metadata cache if it doesn't exist or is older than source
    if [ ! -f "$cache_file" ] || [ "$file" -nt "$cache_file" ]; then
        # Use grep -n and sed to extract frontmatter block efficiently
        local frontmatter_lines
        frontmatter_lines=$(grep -n "^---$" "$file" | cut -d: -f1)
        local start_line=$(echo "$frontmatter_lines" | head -n 1)
        local end_line=$(echo "$frontmatter_lines" | head -n 2 | tail -n 1)

        # Check if valid start and end lines were found
        if [[ -n "$start_line" && -n "$end_line" && $start_line -lt $end_line ]]; then
            # Extract frontmatter, remove leading/trailing whitespace, and save to cache
            sed -n "$((start_line+1)),$((end_line-1))p" "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$cache_file"
        else
            # No valid frontmatter found, create empty cache file
             > "$cache_file"
        fi
    fi

    # Read from cache if it exists
    if [ -f "$cache_file" ]; then
        # Use grep -m 1 for efficiency
        value=$(grep -m 1 "^$field:[[:space:]]*" "$cache_file" | cut -d ':' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    # Release lock
    unlock_file "$cache_file"

    # Fallback to direct file read ONLY if cache read failed (should be rare)
    if [ -z "$value" ]; then
        local frontmatter_lines
        frontmatter_lines=$(grep -n "^---$" "$file" | cut -d: -f1)
        local start_line=$(echo "$frontmatter_lines" | head -n 1)
        local end_line=$(echo "$frontmatter_lines" | head -n 2 | tail -n 1)

        if [[ -n "$start_line" && -n "$end_line" && $start_line -lt $end_line ]]; then
            value=$(sed -n "$((start_line+1)),$((end_line-1))p" "$file" | grep -m 1 "^$field:[[:space:]]*" | cut -d ':' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
    fi

    echo "$value"
}

# Extract metadata from markdown file (builds cache)
extract_metadata() {
    local file="$1"
    local metadata_cache_file="${CACHE_DIR:-.bssg_cache}/meta/$(basename "$file")"
    local frontmatter_changes_marker="${CACHE_DIR:-.bssg_cache}/frontmatter_changes_marker"
    local ram_mode_active=false
    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$file"; then
        ram_mode_active=true
    fi

    # Check if file exists
    if ! $ram_mode_active && [ ! -f "$file" ]; then
        echo "ERROR_FILE_NOT_FOUND"
        return 1
    fi

    # Flag to track whether frontmatter has changed
    local frontmatter_changed=false

    # Check if cache exists and is newer than the source file
    if ! $ram_mode_active && [ "${FORCE_REBUILD:-false}" = false ] && [ -f "$metadata_cache_file" ] && [ "$metadata_cache_file" -nt "$file" ]; then
        # Read from cache file (optimized - read once)
        echo "$(cat "$metadata_cache_file")"
        return 0
    else
        # If we're regenerating metadata, assume it changed for index rebuilding purposes
        frontmatter_changed=true
    fi

    # If we're here, we need to parse the file
    local title="" date="" lastmod="" tags="" slug="" image="" image_caption="" description="" author_name="" author_email=""

    # Check file type and parse accordingly
    if [[ "$file" == *.html ]]; then
        # Parse <meta> tags for HTML files
        # Use grep -m 1 for efficiency, handle missing tags gracefully
        # Note: This is basic parsing, assumes simple meta tag structure.
        local html_source=""
        if $ram_mode_active; then
            html_source=$(ram_mode_get_content "$file")
            title=$(printf '%s\n' "$html_source" | grep -m 1 -o '<title>[^<]*</title>' 2>/dev/null | sed -e 's/<title>//' -e 's/<\/title>//')
            date=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="date" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            lastmod=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="lastmod" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            tags=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="tags" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            slug=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="slug" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            image=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="image" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            image_caption=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="image_caption" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            description=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="description" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            author_name=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="author_name" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            author_email=$(printf '%s\n' "$html_source" | grep -m 1 -o 'name="author_email" content="[^"]*"' 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        else
            title=$(grep -m 1 -o '<title>[^<]*</title>' "$file" 2>/dev/null | sed -e 's/<title>//' -e 's/<\/title>//')
            date=$(grep -m 1 -o 'name="date" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            lastmod=$(grep -m 1 -o 'name="lastmod" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            tags=$(grep -m 1 -o 'name="tags" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            slug=$(grep -m 1 -o 'name="slug" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            image=$(grep -m 1 -o 'name="image" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            image_caption=$(grep -m 1 -o 'name="image_caption" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            description=$(grep -m 1 -o 'name="description" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            author_name=$(grep -m 1 -o 'name="author_name" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
            author_email=$(grep -m 1 -o 'name="author_email" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        fi
        # Note: Excerpt generation (fallback for description) might not work well for HTML

    elif [[ "$file" == *.md ]]; then
        # Parse YAML frontmatter for Markdown files
        # Use a shared awk parser for both disk and RAM paths.
        local parsed_data
        local awk_frontmatter_parser
        awk_frontmatter_parser=$(cat <<'EOF'
        BEGIN {
            in_fm = 0;
            found_fm = 0;
            # Define default empty values
            vars["title"] = ""; vars["date"] = ""; vars["lastmod"] = "";
            vars["tags"] = ""; vars["slug"] = ""; vars["image"] = "";
            vars["image_caption"] = ""; vars["description"] = "";
            vars["author_name"] = ""; vars["author_email"] = "";
        }
        /^---$/ {
            if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
            if (in_fm) { in_fm = 0; exit; } # Exit awk early after frontmatter
        }
        in_fm {
            # Match key: value, trim whitespace
            local key value
            if (match($0, /^([^:]+):[[:space:]]*(.*[^[:space:]])[[:space:]]*$/)) {
                key = substr($0, RSTART, RLENGTH);
                # Extract key part
                match(key, /^[^:]+/);
                key_str = substr(key, RSTART, RLENGTH);
                # Extract value part
                match(key, /:[[:space:]]*(.*)$/);
                value = substr(key, RSTART + 1, RLENGTH -1 ); # +1/-1 to skip the :
                # Trim spaces from key and value
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key_str);
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value);
                key = tolower(key_str);

                # Handle quoted strings (optional, basic handling)
                if ( (match(value, /^"(.*)"$/) || match(value, /^\'(.*)\'$/)) && length(value) > 1 ) {
                   value = substr(value, 2, length(value)-2);
                }
                vars[key] = value;
            }
        }
        END {
            # Print values in specific order
            print vars["title"] "|" vars["date"] "|" vars["lastmod"] "|" \
                  vars["tags"] "|" vars["slug"] "|" vars["image"] "|" \
                  vars["image_caption"] "|" vars["description"] "|" \
                  vars["author_name"] "|" vars["author_email"];
        }
EOF
        )

        if $ram_mode_active; then
            parsed_data=$(printf '%s\n' "$(ram_mode_get_content "$file")" | awk "$awk_frontmatter_parser")
        else
            parsed_data=$(awk "$awk_frontmatter_parser" "$file")
        fi
        
        IFS='|' read -r title date lastmod tags slug image image_caption description author_name author_email <<< "$parsed_data"

    else
        echo "Warning: Unknown file type '$file' for metadata extraction." >&2
    fi

    # Fallbacks for missing metadata
    if [ -z "$title" ]; then
        title=$(basename "$file" | sed 's/\\\\.[^.]*$//')
    fi
    if [ -z "$date" ]; then
        local file_mtime=$(get_file_mtime "$file")
        date=$(format_date_from_timestamp "$file_mtime")
    fi
    # Fallback for lastmod: use date if lastmod is empty
    if [ -z "$lastmod" ]; then
        lastmod="$date"
    fi
       if [ -z "$slug" ]; then
        slug=$(generate_slug "$title")
    else
        slug=$(generate_slug "$slug")
    fi
    if [ -z "$description" ]; then
        # Generate excerpt only if description is missing
        # The excerpt is already sanitized and HTML-escaped plain text
        echo "[DEBUG] Generating excerpt for $file" >&2
        description=$(generate_excerpt "$file")
    fi
    
    # Apply fallback logic for author fields
    if [ -z "$author_name" ]; then
        author_name="${AUTHOR_NAME:-Anonymous}"
    fi
    if [ -z "$author_email" ] && [ -n "$author_name" ] && [ "$author_name" = "${AUTHOR_NAME:-Anonymous}" ]; then
        # Only use default email if using default name
        author_email="${AUTHOR_EMAIL:-anonymous@example.com}"
    fi
    # If author_name is specified but author_email is empty, leave email empty

    # Construct the metadata string for comparison and caching
    local new_metadata="$title|$date|$lastmod|$tags|$slug|$image|$image_caption|$description|$author_name|$author_email"

    # Check if there was a previous metadata file and compare
    if ! $ram_mode_active && [ -f "$metadata_cache_file" ]; then
        local old_metadata=$(cat "$metadata_cache_file")
        if [ "$old_metadata" != "$new_metadata" ]; then
            frontmatter_changed=true
        fi
    fi

    # Store all metadata in one write operation
    if ! $ram_mode_active; then
        lock_file "$metadata_cache_file"
        mkdir -p "$(dirname "$metadata_cache_file")"
        echo "$new_metadata" > "$metadata_cache_file"
        unlock_file "$metadata_cache_file"
    fi

    # If frontmatter has changed, update the marker file's timestamp
    if ! $ram_mode_active && $frontmatter_changed; then
        touch "$frontmatter_changes_marker"
    fi

    # Return the metadata as pipe-separated values
    echo "$new_metadata"
}

# Generate an excerpt from post content
generate_excerpt() {
    local file="$1"
    local max_length="${2:-160}"  # Default to 160 characters

    local raw_content_stream
    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_has_file > /dev/null && ram_mode_has_file "$file"; then
        # Remove frontmatter directly from preloaded content
        raw_content_stream=$(printf '%s\n' "$(ram_mode_get_content "$file")" | awk '
            BEGIN { in_fm = 0; found_fm = 0; }
            /^---$/ {
                if (!in_fm && !found_fm) { in_fm = 1; found_fm = 1; next; }
                if (in_fm) { in_fm = 0; next; }
            }
            { if (!in_fm) print; }
        ')
    else
        # Extract content after frontmatter
        local start_line end_line
        start_line=$(grep -n "^---$" "$file" | head -1 | cut -d: -f1)
        end_line=$(grep -n "^---$" "$file" | head -n 2 | tail -1 | cut -d: -f1)

        if [[ -n "$start_line" && -n "$end_line" && $start_line -lt $end_line ]]; then
            # Stream content after frontmatter
            raw_content_stream=$(tail -n +$((end_line + 1)) "$file")
        else
            # No valid frontmatter, stream the whole file
            raw_content_stream=$(cat "$file")
        fi
    fi

    # Sanitize and extract the first non-empty paragraph/line
    # Apply sanitization steps sequentially
    local sanitized_content
    sanitized_content=$(echo "$raw_content_stream" | \
        # Remove code blocks (``` and indented)
        awk '/^```/{flag=!flag;next} !flag;' | grep -v '^```' | \
        grep -v '^    ' | \
        # Remove images, links, headings, hr, blockquotes
        sed -E 's/!\[([^]]*)\]\([^)]*\)//g' | \
        sed -E 's/\[([^]]+)\]\(([^)]+)\)/\1/g' | \
        sed 's/^#\{1,6\} //' | \
        grep -v '^---\+$' | \
        grep -v '^\*\*\*\+$' | \
        grep -v '^___\+$' | \
        sed 's/^> //' | \
        # Remove list markers
        sed -E 's/^\* |^- |^[0-9]+\. //' | \
        # Remove inline markdown: bold, italics, strikethrough, code
        sed -E 's/\*\*([^*]+)\*\*/\1/g; s/__([^_]+)__/\1/g' | \
        sed -E 's/\*([^*]+)\*/\1/g; s/_([^_]+)_/\1/g' | \
        sed -E 's/~~([^~]+)~~/\1/g' | \
        sed -E 's/`([^`]+)`/\1/g' | \
        # Remove HTML tags
        sed -E 's/<[^>]*>//g' | \
        # Escape basic HTML entities (ampersand, less than, greater than)
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | \
        # Remove extra blank lines
        awk 'NF {p=1} p' | \
        # Get the first non-empty line (first paragraph)
        awk 'NF {print; exit}' 
    )

    # Truncate to max length using dd for portability
    local excerpt
    if [ -z "$sanitized_content" ]; then
        excerpt=""
    else
        # Use dd: bs=1 reads byte by byte, count limits the total bytes
        # 2>/dev/null suppresses dd's status messages
        excerpt=$(echo "$sanitized_content" | dd bs=1 count="$max_length" 2>/dev/null)
    fi

    # Add ellipsis if truncated
    if [ ${#sanitized_content} -gt $max_length ]; then
        excerpt+="..."
    fi
    
    # Ensure description is not empty after all this
    if [ -z "$excerpt" ]; then
        # Fallback: use the filename if excerpt is still empty
        excerpt=$(basename "$file" | sed 's/\.[^.]*$//')
    fi

    echo "$excerpt"
}

# Convert provided markdown content string to HTML
convert_markdown_to_html() {
    local content="$1" # Expect markdown content as the first argument
    local html_content=""

    # IMPORTANT: Assumes MARKDOWN_PROCESSOR, MARKDOWN_PL_PATH are exported/available
    # IMPORTANT: Assumes required processor (pandoc, cmark, perl) is installed

    if [ "${MARKDOWN_PROCESSOR:-pandoc}" = "pandoc" ]; then
        if ! html_content=$(echo "$content" | pandoc -f markdown -t html); then
            echo -e "${RED}Error: Markdown conversion failed using pandoc.${NC}" >&2
            return 1
        fi
    elif [ "$MARKDOWN_PROCESSOR" = "commonmark" ]; then
        if ! html_content=$(echo "$content" | cmark); then
            echo -e "${RED}Error: Markdown conversion failed using cmark.${NC}" >&2
            return 1
        fi
    elif [ "$MARKDOWN_PROCESSOR" = "markdown.pl" ]; then
        # Preprocess content to handle fenced code blocks for markdown.pl
        local preprocessed_content="$content"
        # Handle fenced code blocks (``` and ~~~) -> indented
        # Requires awk
        if command -v awk &> /dev/null; then
            preprocessed_content=$(printf '%s' "$preprocessed_content" | awk '
                BEGIN { in_code = 0; }
                /^```[a-zA-Z0-9]*$/ || /^~~~[a-zA-Z0-9]*$/ { if (!in_code) { in_code = 1; print ""; next; } }
                /^```$/ || /^~~~$/ { if (in_code) { in_code = 0; print ""; next; } }
                { if (in_code) { print "    " $0; } else { print $0; } }
            ')
        else
            echo -e "${YELLOW}Warning: awk not found, markdown.pl fenced code block conversion skipped.${NC}" >&2
            # Content remains as original if awk fails
            preprocessed_content="$content"
        fi

        # Ensure MARKDOWN_PL_PATH is set and executable
        if [ -z "$MARKDOWN_PL_PATH" ] || [ ! -x "$MARKDOWN_PL_PATH" ]; then
             echo -e "${RED}Error: MARKDOWN_PL_PATH ('$MARKDOWN_PL_PATH') not set or not executable.${NC}" >&2
             return 1
        fi

        # Use printf to pipe content to avoid issues with content starting with -
        if ! html_content=$(printf '%s' "$preprocessed_content" | perl "$MARKDOWN_PL_PATH"); then
            echo -e "${RED}Error: Markdown conversion failed using markdown.pl.${NC}" >&2
            return 1
        fi
    else
        echo -e "${RED}Error: Unknown MARKDOWN_PROCESSOR ('$MARKDOWN_PROCESSOR'). Cannot convert content.${NC}" >&2
        return 1
    fi

    echo "$html_content" # Output the result
    return 0
}

# --- Content Functions --- END --- 
