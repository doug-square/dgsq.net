#!/usr/bin/env bash
#
# BSSG - Content Processing Utilities
# Functions for parsing metadata, generating excerpts, and converting markdown.
#

# Ensure necessary color variables are available if sourced independently
# RED='${RED:-\033[0;31m}'
# GREEN='${GREEN:-\033[0;32m}'
# YELLOW='${YELLOW:-\033[0;33m}'
# NC='${NC:-\033[0m}'

# Source Utilities if needed by functions below
# shellcheck source=utils.sh disable=SC1091
source "$(dirname "$0")/utils.sh" || { echo >&2 "Error: Failed to source utils.sh from content.sh"; exit 1; }

# --- Content Functions --- START ---

# Parse metadata from a markdown file (uses cache)
parse_metadata() {
    local file="$1"
    local field="$2"

    # IMPORTANT: Assumes CACHE_DIR is exported/available
    local cache_file="${CACHE_DIR:-.bssg_cache}/meta/$(basename "$file")"
    local value=""

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

    # Check if file exists
    if [ ! -f "$file" ]; then
        echo "ERROR_FILE_NOT_FOUND"
        return 1
    fi

    # Flag to track whether frontmatter has changed
    local frontmatter_changed=false

    # Check if cache exists and is newer than the source file
    if [ "${FORCE_REBUILD:-false}" = false ] && [ -f "$metadata_cache_file" ] && [ "$metadata_cache_file" -nt "$file" ]; then
        # Read from cache file (optimized - read once)
        echo "$(cat "$metadata_cache_file")"
        return 0
    else
        # If we're regenerating metadata, assume it changed for index rebuilding purposes
        frontmatter_changed=true
    fi

    # If we're here, we need to parse the file
    local title="" date="" lastmod="" tags="" slug="" image="" image_caption="" description=""

    # Check file type and parse accordingly
    if [[ "$file" == *.html ]]; then
        # Parse <meta> tags for HTML files
        # Use grep -m 1 for efficiency, handle missing tags gracefully
        # Note: This is basic parsing, assumes simple meta tag structure.
        title=$(grep -m 1 -o '<title>[^<]*</title>' "$file" 2>/dev/null | sed -e 's/<title>//' -e 's/<\/title>//')
        date=$(grep -m 1 -o 'name="date" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        lastmod=$(grep -m 1 -o 'name="lastmod" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        tags=$(grep -m 1 -o 'name="tags" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        slug=$(grep -m 1 -o 'name="slug" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        image=$(grep -m 1 -o 'name="image" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        image_caption=$(grep -m 1 -o 'name="image_caption" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        description=$(grep -m 1 -o 'name="description" content="[^"]*"' "$file" 2>/dev/null | sed 's/.*content="\([^"]*\)".*/\1/')
        # Note: Excerpt generation (fallback for description) might not work well for HTML

    elif [[ "$file" == *.md ]]; then
        # Parse YAML frontmatter for Markdown files
        local in_frontmatter=false
        local found_frontmatter=false
        {
            while IFS= read -r line; do
                # Trim leading/trailing whitespace from line
                line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                if [[ "$line" == "---" ]]; then
                    if ! $in_frontmatter && ! $found_frontmatter; then
                        in_frontmatter=true
                        found_frontmatter=true
                        continue
                    elif $in_frontmatter; then
                        in_frontmatter=false
                        # Stop reading after frontmatter is closed
                        break
                    fi
                fi

                if $in_frontmatter; then
                    # Parse each frontmatter field (case-insensitive key matching)
                    local key value
                    if [[ "$line" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
                        key=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
                        value="${BASH_REMATCH[2]}"

                        case "$key" in
                            title)
                                title="$value"
                                ;;
                            date)
                                date="$value"
                                ;;
                            lastmod)
                                lastmod="$value"
                                ;;
                            tags)
                                tags="$value"
                                ;;
                            slug)
                                slug="$value"
                                ;;
                            image)
                                image="$value"
                                ;;
                            image_caption)
                                image_caption="$value"
                                ;;
                            description)
                                description="$value"
                                ;;
                        esac
                    fi
                fi
            done
        } < "$file"
    else
        echo "Warning: Unknown file type '$file' for metadata extraction." >&2
    fi

    # Fallbacks for missing metadata
    if [ -z "$title" ]; then
        title=$(basename "$file" | sed 's/\\.[^.]*$//')
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
    fi
    if [ -z "$description" ]; then
        # Generate excerpt only if description is missing
        local plain_excerpt
        plain_excerpt=$(generate_excerpt "$file")
        # Convert the plain text excerpt to HTML
        description=$(convert_markdown_to_html "$plain_excerpt")
        # Basic fallback if conversion somehow fails, use the plain excerpt
        if [ $? -ne 0 ] || [ -z "$description" ]; then
             echo "Warning: Failed to convert generated excerpt to HTML for $file. Using plain text excerpt." >&2
             description="$plain_excerpt"
        fi
    fi

    # Construct the metadata string for comparison and caching
    local new_metadata="$title|$date|$lastmod|$tags|$slug|$image|$image_caption|$description"

    # Check if there was a previous metadata file and compare
    if [ -f "$metadata_cache_file" ]; then
        local old_metadata=$(cat "$metadata_cache_file")
        if [ "$old_metadata" != "$new_metadata" ]; then
            frontmatter_changed=true
        fi
    fi

    # Store all metadata in one write operation
    lock_file "$metadata_cache_file"
    mkdir -p "$(dirname "$metadata_cache_file")"
    echo "$new_metadata" > "$metadata_cache_file"
    unlock_file "$metadata_cache_file"

    # If frontmatter has changed, update the marker file's timestamp
    if $frontmatter_changed; then
        touch "$frontmatter_changes_marker"
    fi

    # Return the metadata as pipe-separated values
    echo "$new_metadata"
}

# Generate an excerpt from post content
generate_excerpt() {
    local file="$1"
    local max_length="${2:-160}"  # Default to 160 characters

    # Extract content after frontmatter
    local start_line=$(grep -n "^---$" "$file" | head -1 | cut -d: -f1)
    local end_line=$(grep -n "^---$" "$file" | head -2 | tail -1 | cut -d: -f1)

    local content=""
    if [[ -z "$start_line" || -z "$end_line" || ! $start_line -lt $end_line ]]; then
        # No valid frontmatter, use the beginning of the file
        content=$(head -n 50 "$file")
    else
        # Extract content after frontmatter
        content=$(tail -n +$((end_line + 1)) "$file" | head -n 50)
    fi

    # Comprehensive markdown sanitization

    # 1. Remove code blocks (both ```code``` and indented)
    content=$(echo "$content" | awk '/^```/{flag=!flag;next} !flag;' | grep -v '^```')
    content=$(echo "$content" | grep -v '^    ')

    # Process line by line to handle multiline patterns better
    content=$(echo "$content" | while IFS= read -r line; do
        # 2. Remove images ![alt](url)
        line=$(echo "$line" | sed -E 's/!\[([^]]*)\]\([^)]*\)//g')

        # 3. Replace links [text](url) with just text
        line=$(echo "$line" | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g')

        # 4. Remove HTML tags
        line=$(echo "$line" | sed -E 's/<[^>]*>//g')

        # 5. Remove headers (# Header)
        line=$(echo "$line" | sed -E 's/^#+ +//g')

        # 6. Remove emphasis/code markers (*, _, `)
        line=$(echo "$line" | sed -E 's/(\*\*|__|\*|_|`)([^\*`_]+)(\1)/\2/g')

        # 7. Remove blockquotes (> text)
        line=$(echo "$line" | sed -E 's/^> +//g')

        # 8. Remove list markers (*, +, -, 1.)
        line=$(echo "$line" | sed -E 's/^([*+-]|[0-9]+\.) +//g')

        # 9. Remove horizontal rules (---, ___, ***)
        if ! echo "$line" | grep -qE '^[[:space:]]*([-*_])([[:space:]]*\1){2,}[[:space:]]*$'; then
            echo "$line"
        fi
    done)

    # 10. Normalize whitespace and remove extra line breaks
    content=$(echo "$content" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 11. Escape HTML special characters (basic set)
    content=$(echo "$content" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/\x27/\&apos;/g')

    # Truncate to approximately max_length chars at word boundary
    local truncated
    if [ ${#content} -gt $max_length ]; then
        truncated=$(echo "$content" | cut -c 1-$max_length)
        # Remove trailing partial word
        truncated=${truncated% * }
        # Add ellipsis if truncation occurred
        if [ "$truncated" != "$content" ]; then
            truncated="${truncated}..."
        fi
    else
        truncated="$content"
    fi

    echo "$truncated"
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
        local temp_file
        temp_file=$(mktemp)
        # Use printf to avoid issues with content starting with -
        printf '%s' "$preprocessed_content" > "$temp_file"

        # Handle fenced code blocks (``` and ~~~) -> indented
        # Requires awk
        if command -v awk &> /dev/null; then
            preprocessed_content=$(awk '
                BEGIN { in_code = 0; }
                /^```[a-zA-Z0-9]*$/ || /^~~~[a-zA-Z0-9]*$/ { if (!in_code) { in_code = 1; print ""; next; } }
                /^```$/ || /^~~~$/ { if (in_code) { in_code = 0; print ""; next; } }
                { if (in_code) { print "    " $0; } else { print $0; } }
            ' "$temp_file")
            rm "$temp_file"
        else
            echo -e "${YELLOW}Warning: awk not found, markdown.pl fenced code block conversion skipped.${NC}" >&2
            # Content remains as original if awk fails
             preprocessed_content=$(cat "$temp_file")
             rm "$temp_file"
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