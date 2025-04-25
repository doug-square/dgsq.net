#!/usr/bin/env bash
#
# BSSG - List Posts and Tags Script
# List all posts and tags in the blog
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

set -e

# Configuration is now loaded and exported by the main bssg.sh script
# via config_loader.sh. This script relies on environment variables like
# SRC_DIR, PAGES_DIR, DRAFTS_DIR etc. being set.

# Terminal colors definitions removed, assuming they are exported by the caller.

# Function to extract a post's title
get_post_title() {
    local file="$1"
    local title=""
    
    if [[ "$file" == *.md ]]; then
        title=$(grep -m 1 "^title:" "$file" | cut -d ':' -f 2- | sed 's/^ *//' | tr -d \'\"\')
    elif [[ "$file" == *.html ]]; then
        title=$(grep -m 1 "<title>" "$file" | sed -e 's/<title>//' -e 's/<\/title>//' | sed 's/^ *//' | tr -d \'\"\')
    fi
    
    # If no title found, use filename without extension
    if [ -z "$title" ]; then
        title=$(basename "$file" | sed 's/\.[^.]*$//')
    fi
    
    echo "$title"
}

# Function to extract a post's date
get_post_date() {
    local file="$1"
    local date=""
    
    if [[ "$file" == *.md ]]; then
        date=$(grep -m 1 "^date:" "$file" | cut -d ':' -f 2- | sed 's/^ *//')
    elif [[ "$file" == *.html ]]; then
        date=$(grep -m 1 'content="[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}"' "$file" | sed 's/.*content="\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)".*/\1/')
    fi
    
    # If no date found, use file modification time
    if [ -z "$date" ]; then
        if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]]; then
            # macOS or FreeBSD
            date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file")
        else
            # Linux and others
            date=$(stat -c "%y" "$file" | cut -d ' ' -f 1)
        fi
    fi
    
    echo "$date"
}

# Function to extract a post's tags
get_post_tags() {
    local file="$1"
    local tags=""
    
    if [[ "$file" == *.md ]]; then
        tags=$(grep -m 1 "^tags:" "$file" | cut -d ':' -f 2- | sed 's/^ *//' | tr -d \'\"\')
    elif [[ "$file" == *.html ]]; then
        tags=$(grep -m 1 '<meta name="tags"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
    fi
    
    echo "$tags"
}

# Function to list content items (posts or pages) in a given directory
list_content_in_dir() {
    local dir_path="$1"
    local content_type_name="$2" # e.g., "posts", "pages", "drafts"

    echo -e "${YELLOW}Available $content_type_name in '$dir_path':${NC}"

    if [ ! -d "$dir_path" ] || [ -z "$(ls -A "$dir_path" 2>/dev/null)" ]; then
        echo -e "${RED}No $content_type_name found in '$dir_path'.${NC}"
        return
    fi

    echo -e "Path\t\t\t\tDate\t\tTitle"
    echo -e "----\t\t\t\t----\t\t-----"

    local counter=1
    find "$dir_path" -maxdepth 1 -type f \( -name "*.md" -o -name "*.html" \) | sort -r | while read -r file; do
        local title=$(get_post_title "$file") # Reusing post title logic
        local date=$(get_post_date "$file")   # Reusing post date logic
        local display_path=$(basename "$file") # Show only filename for brevity

        # Basic tabbing for alignment (can be improved)
        local tabs="\t\t\t\t"
        if [ ${#display_path} -gt 23 ]; then
            tabs="\t\t"
        elif [ ${#display_path} -gt 15 ]; then
            tabs="\t\t\t"
        elif [ ${#display_path} -gt 7 ]; then
            tabs="\t\t\t\t"
        fi

        # Show relative path for clarity
        echo -e "$file$tabs$date\t$title"
        counter=$((counter + 1))
    done
}

# Function to get a count of posts with a specific tag
count_posts_with_tag() {
    local tag="$1"
    local count=0
    
    find "$SRC_DIR" -type f \( -name "*.md" -o -name "*.html" \) | while read -r file; do
        local tags=$(get_post_tags "$file")
        
        if [[ ",$tags," == *",$tag,"* ]] || [[ "$tags" == "$tag" ]]; then
            count=$((count + 1))
        fi
    done
    
    echo $count
}

# Function to list all tags
list_tags() {
    local sort_by_count=false
    
    # Parse arguments
    if [ "$1" = "-n" ]; then
        sort_by_count=true
    fi
    
    echo -e "${YELLOW}Available tags (from posts in '$SRC_DIR'):${NC}"
    
    if [ ! -d "$SRC_DIR" ] || [ -z "$(ls -A "$SRC_DIR" 2>/dev/null)" ]; then
        echo -e "${RED}No posts found in '$SRC_DIR' to extract tags from.${NC}"
        exit 0
    fi
    
    # Collect all tags from all posts in SRC_DIR
    local all_tags=""
    
    for file in $(find "$SRC_DIR" -type f \( -name "*.md" -o -name "*.html" \)); do
        local tags=""
        
        if [[ "$file" == *.md ]]; then
            tags=$(grep -m 1 "^tags:" "$file" | cut -d ':' -f 2- | sed 's/^ *//' | tr -d \'\"\')
        elif [[ "$file" == *.html ]]; then
            tags=$(grep -m 1 '<meta name="tags"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
        fi
        
        # Only process if tags exist
        if [ -n "$tags" ]; then
            # Split by comma and add to all_tags
            IFS=',' read -ra TAG_ARRAY <<< "$tags"
            for tag in "${TAG_ARRAY[@]}"; do
                # Remove leading/trailing whitespace
                tag=$(echo "$tag" | sed 's/^ *//;s/ *$//')
                # Ensure tag is not empty before adding comma
                if [ -n "$tag" ]; then 
                    all_tags="$all_tags,$tag"
                fi
            done
        fi
    done
    
    # Remove leading comma if exists
    all_tags=${all_tags#,}
    
    # Sort and remove duplicates
    local unique_tags=$(echo "$all_tags" | tr ',' '\n' | sort -u | grep .)
    
    # If no tags found
    if [ -z "$unique_tags" ]; then
        echo -e "${RED}No tags found in any posts.${NC}"
        exit 0
    fi
    
    if [ "$sort_by_count" = true ]; then
        echo -e "Tag\t\t\tCount"
        echo -e "---\t\t\t-----"
        
        # Create temporary file
        local temp_file=$(mktemp)
        
        # Get count for each tag and write to temp file
        echo "$unique_tags" | while read -r tag; do
            if [ -n "$tag" ]; then
                local count=0
                
                for file in $(find "$SRC_DIR" -type f \( -name "*.md" -o -name "*.html" \)); do
                    local file_tags=""
                    
                    if [[ "$file" == *.md ]]; then
                        file_tags=$(grep -m 1 "^tags:" "$file" | cut -d ':' -f 2- | sed 's/^ *//' | tr -d \'\"\')
                    elif [[ "$file" == *.html ]]; then
                        file_tags=$(grep -m 1 '<meta name="tags"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
                    fi
                    
                    # Check if tag exists in file_tags (handle comma-separated lists)
                    if [[ ",$file_tags," == *",$tag,"* ]] || [[ "$file_tags" == "$tag" ]]; then
                        count=$((count + 1))
                    fi
                done
                
                echo -e "$tag\t$count" >> "$temp_file"
            fi
        done
        
        # Sort by count (descending) and display
        sort -t$'\t' -k2nr -k1 "$temp_file" | while read -r line; do
            local tag=$(echo "$line" | cut -f1)
            local count=$(echo "$line" | cut -f2)
            
            # Adjust tabbing based on tag length
            local tabs="\t\t\t"
            if [ ${#tag} -gt 15 ]; then
                tabs="\t"
            elif [ ${#tag} -gt 7 ]; then
                tabs="\t\t"
            fi
            
            echo -e "$tag$tabs$count"
        done
        
        # Clean up
        rm "$temp_file"
    else
        echo -e "Tag\t\t\tCount"
        echo -e "---\t\t\t-----"
        
        # Create temporary file for counts
        local temp_counts=$(mktemp)

        # Count tags
        for tag in $unique_tags; do
            if [ -n "$tag" ]; then
                local count=0
                for file in $(find "$SRC_DIR" -type f \( -name "*.md" -o -name "*.html" \)); do
                    local file_tags=""
                    if [[ "$file" == *.md ]]; then
                        file_tags=$(grep -m 1 "^tags:" "$file" | cut -d ':' -f 2- | sed 's/^ *//' | tr -d \'\"\')
                    elif [[ "$file" == *.html ]]; then
                        file_tags=$(grep -m 1 '<meta name="tags"' "$file" | sed 's/.*content="\([^"]*\)".*/\1/')
                    fi
                    # Check if tag exists in file_tags (handle comma-separated lists)
                    if [[ ",$file_tags," == *",$tag,"* ]] || [[ "$file_tags" == "$tag" ]]; then
                        count=$((count + 1))
                    fi
                done
                echo -e "$tag\t$count" >> "$temp_counts"
            fi
        done

        # Sort alphabetically by tag name and display
        sort -t$'\t' -k1 "$temp_counts" | while read -r line; do
             local tag=$(echo "$line" | cut -f1)
            local count=$(echo "$line" | cut -f2)
            
            # Adjust tabbing based on tag length
            local tabs="\t\t\t"
            if [ ${#tag} -gt 15 ]; then
                tabs="\t"
            elif [ ${#tag} -gt 7 ]; then
                tabs="\t\t"
            fi
            
            echo -e "$tag$tabs$count"
        done

        # Clean up
        rm "$temp_counts"
    fi
}

# Main function
main() {
    local command="posts"
    
    # Parse arguments
    if [ -n "$1" ]; then
        command="$1"
        shift
    fi
    
    case "$command" in
        posts)
            list_content_in_dir "$SRC_DIR" "posts"
            ;;
        pages)
            list_content_in_dir "$PAGES_DIR" "pages"
            ;;
        drafts)
            list_content_in_dir "$DRAFTS_DIR" "post drafts"
            list_content_in_dir "$DRAFTS_DIR/pages" "page drafts"
            ;;
        tags)
            list_tags "$@"
            ;;
        *)
            echo -e "${RED}Error: Unknown list command '$command'${NC}"
            echo -e "Usage: $0 {posts|pages|drafts|tags [-n]}"
            exit 1
            ;;
    esac
}

# Run the main function
main "$@" 