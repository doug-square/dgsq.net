#!/usr/bin/env bash
#
# BSSG - Indexing Utilities
# Functions for building intermediate file, tag, and archive indexes.
#

# Ensure necessary color variables are available if sourced independently
# RED='${RED:-\033[0;31m}' # Removed - Should be inherited from main export
# GREEN='${GREEN:-\033[0;32m}' # Removed - Should be inherited from main export
# YELLOW='${YELLOW:-\033[0;33m}' # Removed - Should be inherited from main export
# NC='${NC:-\033[0m}' # Removed - Should be inherited from main export

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

# Optimized file index building with parallel processing and smarter caching
optimized_build_file_index() {
    echo -e "${YELLOW}Building file index...${NC}"
    
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local index_marker="${CACHE_DIR:-.bssg_cache}/index_marker"
    local frontmatter_changes_marker="${CACHE_DIR:-.bssg_cache}/frontmatter_changes_marker"
    
    # Check if rebuild is needed by comparing the newest file in src directory with our marker
    if [ "${FORCE_REBUILD:-false}" = false ] && [ -f "$file_index" ] && [ -f "$index_marker" ]; then
        local newest_file_time=0
        # Use find -printf for efficiency if available (GNU find)
        if find --version >/dev/null 2>&1 && grep -q GNU <<< "$(find --version)"; then
             newest_file_time=$(find "${SRC_DIR:-src}" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" -printf '%T@\n' 2>/dev/null | sort -nr | head -n 1)
             newest_file_time=${newest_file_time:-0} # Handle empty dir
             # Convert float timestamp to integer
             newest_file_time=$(printf "%.0f" "$newest_file_time")
        else
            # Fallback for non-GNU find (less efficient)
            local src_files
            src_files=$(find "${SRC_DIR:-src}" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" 2>/dev/null)
            for f in $src_files; do
                local f_time=$(get_file_mtime "$f")
                if (( f_time > newest_file_time )); then
                    newest_file_time=$f_time
                fi
            done
        fi
        
        local marker_time=$(get_file_mtime "$index_marker")
        
        if [ "$newest_file_time" -le "$marker_time" ]; then
            echo -e "${GREEN}File index is up to date, skipping...${NC}"
            return 0
        fi
    fi
    
    lock_file "$file_index"
    
    # Find all markdown/html files in the source directory, excluding hidden
    local all_files_tmp="${CACHE_DIR:-.bssg_cache}/all_files.tmp.$$"
    find "${SRC_DIR:-src}" -type f \( -name "*.md" -o -name "*.html" \) -not -path "*/.*" | sort > "$all_files_tmp"
    
    local total_files=$(wc -l < "$all_files_tmp")
    if [ "$total_files" -eq 0 ]; then
        echo -e "${YELLOW}No source files found in ${SRC_DIR:-src}. Skipping index build.${NC}"
        > "$file_index" # Create empty index
        touch "$index_marker"
        unlock_file "$file_index"
        rm -f "$all_files_tmp"
        return 0
    fi
    echo "Found $total_files files in source directory."
    
    # Create temp directory for parallel processing
    local temp_dir="${CACHE_DIR:-.bssg_cache}/temp_index_$$"
    rm -rf "$temp_dir" # Clean up previous run just in case
    mkdir -p "$temp_dir"
    
    # Ensure metadata cache directory exists
    mkdir -p "${CACHE_DIR:-.bssg_cache}/meta"
    
    # Get number of available CPU cores
    local cores=1
    if command -v nproc > /dev/null 2>&1; then cores=$(nproc); 
    elif command -v sysctl > /dev/null 2>&1; then cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1); fi
    
    # Calculate batch size
    local batch_size=$(( (total_files + cores - 1) / cores ))
    [ "$batch_size" -lt 1 ] && batch_size=1
    
    echo -e "${YELLOW}Processing $total_files files using $cores cores (batch size: $batch_size)...${NC}"
    
    # Export required functions and variables
    export DATE_FORMAT CACHE_DIR SRC_DIR FORCE_REBUILD # Add others as needed
    export -f extract_metadata get_file_mtime format_date_from_timestamp generate_slug generate_excerpt lock_file unlock_file parse_metadata
    
    # Split files into batches
    split -l "$batch_size" "$all_files_tmp" "$temp_dir/batch_"
    rm -f "$all_files_tmp" # Clean up original list
    
    # Function to process a single batch file
    process_batch() {
        local batch_file="$1"
        local output_batch="${batch_file}.out"
        > "$output_batch"  # Initialize empty file
        
        while IFS= read -r file; do
            # Get filename without extension
            local filename=$(basename "$file" | sed 's/\\.[^.]*$//')
            
            # Extract metadata from file
            local metadata
            metadata=$(extract_metadata "$file")
            # Check for errors
            if [[ $? -ne 0 || "$metadata" == "ERROR_FILE_NOT_FOUND" ]]; then
                 echo -e "${RED}Error processing metadata for $file, skipping.${NC}" >&2
                 continue
            fi
            
            local title date lastmod tags slug image image_caption description
            IFS='|' read -r title date lastmod tags slug image image_caption description <<< "$metadata"
            
            # Sanitize description: remove newlines
            description=$(echo "$description" | tr '\n' ' ')

            # Add to batch file
            echo "$file|$filename|$title|$date|$lastmod|$tags|$slug|$image|$image_caption|$description" >> "$output_batch"
        done < "$batch_file"
        rm "$batch_file" # Remove processed input batch
    }
    export -f process_batch

    # Process batches in parallel using GNU Parallel if available
    if command -v parallel > /dev/null 2>&1 && [ "${HAS_PARALLEL:-false}" = true ]; then
        find "$temp_dir" -name "batch_*" -not -name "*.out" | parallel --jobs "$cores" process_batch {}
    else
        # Fallback to sequential processing
        echo -e "${YELLOW}GNU Parallel not found or disabled, processing batches sequentially...${NC}"
        for batch_file in "$temp_dir"/batch_*; do
            [[ "$batch_file" == *.out ]] && continue
            process_batch "$batch_file"
        done
    fi
    
    # Merge batch output files and ensure uniqueness
    local file_index_tmp="${CACHE_DIR:-.bssg_cache}/file_index.tmp.$$"
    find "$temp_dir" -name "*.out" -type f -exec cat {} + > "$file_index_tmp" 2>/dev/null || true
    rm -rf "$temp_dir" # Clean up temp directory

    # Filter by unique file path (first field)
    local file_index_filtered="${CACHE_DIR:-.bssg_cache}/file_index.filtered.$$"
    awk -F'|' '!seen[$1]++' "$file_index_tmp" > "$file_index_filtered"
    rm -f "$file_index_tmp"

    # Sort the filtered index by date (field 4) in reverse chronological order
    local file_index_sorted="${CACHE_DIR:-.bssg_cache}/file_index.sorted.$$"
    # Sort by date field (YYYY-MM-DD HH:MM:SS format). The default string sort works correctly in reverse.
    sort -t '|' -k 4,4r "$file_index_filtered" > "$file_index_sorted"
    rm -f "$file_index_filtered" # Remove the unsorted filtered file

    # Check if file_index has changed
    local index_content_changed=false
    if [ -f "$file_index" ]; then
        if ! cmp -s "$file_index" "$file_index_sorted"; then
            index_content_changed=true
            echo -e "${YELLOW}File index content has changed.${NC}"
        fi
    else
        index_content_changed=true # No previous index exists
    fi

    mv "$file_index_sorted" "$file_index"
    
    # Update frontmatter changes marker if content changed
    if $index_content_changed ; then
        touch "$frontmatter_changes_marker"
        echo -e "${YELLOW}File index changed, updating frontmatter marker.${NC}"
    fi
    
    touch "$index_marker"
    
    unlock_file "$file_index"
    
    echo -e "${GREEN}File index built with $(wc -l < "$file_index") files!${NC}"
}

# Build tags index from the file index
build_tags_index() {
    echo -e "${YELLOW}Building tags index...${NC}"

    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local tags_index_file="${CACHE_DIR:-.bssg_cache}/tags_index.txt"
    local frontmatter_changes_marker="${CACHE_DIR:-.bssg_cache}/frontmatter_changes_marker"

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
    
    > "$tags_index_file"  # Clear the file

    # Read from file index and extract tags
    local line file filename title date lastmod tags slug image image_caption description
    while IFS= read -r line || [[ -n "$line" ]]; do
        IFS='|' read -r file filename title date lastmod tags slug image image_caption description <<< "$line"

        if [ -n "$tags" ]; then
            local tag_slug
            echo "$tags" | tr ',' '\n' | while IFS= read -r tag; do
                # Remove leading/trailing whitespace
                tag=$(echo "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [[ -z "$tag" ]] && continue # Skip empty tags
                
                tag_slug=$(generate_slug "$tag")

                # Output: TagName|TagSlug|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|PostImage|PostImageCaption|PostDescription
                echo "$tag|$tag_slug|$title|$date|$lastmod|$filename.html|$slug|$image|$image_caption|$description" >> "$tags_index_file"
            done
        fi
    done < "$file_index"
    
    unlock_file "$tags_index_file"

    echo -e "${GREEN}Tags index built!${NC}"
}

# Build archive index by year and month from the file index
build_archive_index() {
    echo -e "${YELLOW}Building archive index...${NC}"
    
    local file_index="${CACHE_DIR:-.bssg_cache}/file_index.txt"
    local archive_index_file="${CACHE_DIR:-.bssg_cache}/archive_index.txt"

    # Check if rebuild is needed
    local rebuild_needed=false
    if indexes_need_rebuild; then rebuild_needed=true; 
    elif [ ! -f "$archive_index_file" ]; then rebuild_needed=true; 
    elif [ "$file_index" -nt "$archive_index_file" ]; then 
        echo -e "${YELLOW}File index is newer than archive index, rebuilding archives...${NC}";
        rebuild_needed=true;
    fi

    if ! $rebuild_needed; then
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
    local line file filename title date lastmod tags slug image image_caption description
    while IFS= read -r line || [[ -n "$line" ]]; do
        IFS='|' read -r file filename title date lastmod tags slug image image_caption description <<< "$line"

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

            # Output: Year|MonthNum|MonthName|PostTitle|PostDate|PostLastMod|PostFilename|PostSlug|PostImage|PostImageCaption|PostDescription
            echo "$year|$month|$month_name|$title|$date|$lastmod|$filename.html|$slug|$image|$image_caption|$description" >> "$archive_index_file"
        fi
    done < "$file_index"
    
    unlock_file "$archive_index_file"

    echo -e "${GREEN}Archive index built!${NC}"
}

# --- Indexing Functions --- END --- 