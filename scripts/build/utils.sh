#!/usr/bin/env bash
#
# BSSG - Build Utilities
# Common functions and variables used across build scripts.
#

# Colors for output messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Printing Functions --- START ---
print_error() {
    # Print message in red to stderr
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    # Print message in yellow to stderr
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_success() {
    # Print message in green to stdout
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    # Print message in blue to stdout
    echo -e "${BLUE}[INFO]${NC} $1"
}
# --- Printing Functions --- END ---

# Fix relative URLs to use SITE_URL
fix_url() {
    local url="$1"

    # Skip if URL is already absolute
    if [[ $url == http://* || $url == https://* || $url == //* ]]; then
        echo "$url"
        return
    fi

    # Ensure url starts with / for consistency
    if [[ $url != /* ]]; then
        url="/$url"
    fi

    # Combine SITE_URL with the path
    # IMPORTANT: SITE_URL must be exported or sourced *before* calling this
    local fixed_url="${SITE_URL}${url}"

    echo "$fixed_url"
}

# Format a date string according to the configured DATE_FORMAT
format_date() {
    local input_date="$1"
    local format_override="$2" # Optional format string
    local target_format=${format_override:-"$DATE_FORMAT"} # Use override or global DATE_FORMAT
    local formatted_date
    local kernel_name=$(uname -s) # Get kernel name (e.g., Linux, Darwin, FreeBSD)

    # Skip formatting if date is empty
    if [ -z "$input_date" ]; then
        echo ""
        return
    fi

    # Set TZ environment variable if TIMEZONE is set and not "local"
    local tz_prefix=""
    if [ -n "${TIMEZONE:-}" ] && [ "${TIMEZONE:-local}" != "local" ]; then
        tz_prefix="TZ='${TIMEZONE}' "
    fi

    # Handle "now" input directly
    if [ "$input_date" = "now" ]; then
        # Force C locale for consistent English output and apply TZ
        formatted_date=$(eval "${tz_prefix}LC_ALL=C date +\"$target_format\"" 2>/dev/null || echo "now") # Fallback to "now" if date cmd fails
        echo "$formatted_date"
        return
    fi

    # Try to format the date using the configured format
    # IMPORTANT: DATE_FORMAT must be exported or sourced *before* calling this
    if [[ "$kernel_name" == "Darwin" ]] || [[ "$kernel_name" == *"BSD" ]]; then
        # macOS/BSD date formatting (uses date -j -f)
        # IMPORTANT: Using ISO 8601 format (YYYY-MM-DD HH:MM:SS) in source
        #            files is strongly recommended for portability.

        # Try parsing full ISO date-time first
        formatted_date=$(eval "${tz_prefix}LC_ALL=C date -j -f \"%Y-%m-%d %H:%M:%S\" \"$input_date\" +\"$target_format\"" 2>/dev/null)

        # If failed, try RFC2822 format
        if [ -z "$formatted_date" ]; then
            formatted_date=$(eval "${tz_prefix}LC_ALL=C date -j -f \"%a, %d %b %Y %H:%M:%S %z\" \"$input_date\" +\"$target_format\"" 2>/dev/null)
        fi

        # If still failed, try parsing date-only (YYYY-MM-DD) and assume midnight
        if [ -z "$formatted_date" ]; then
            # Check if input looks like YYYY-MM-DD using shell pattern matching
            if [[ "$input_date" == [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]]; then
                 # Try parsing by appending midnight time
                 formatted_date=$(eval "${tz_prefix}LC_ALL=C date -j -f \"%Y-%m-%d %H:%M:%S\" \"$input_date 00:00:00\" +\"$target_format\"" 2>/dev/null)
            fi
        fi

        # If all parsing attempts failed, fallback to the original input string
        if [ -z "$formatted_date" ]; then
            formatted_date="$input_date"
        fi
    else
        # Assume Linux/GNU date formatting (uses date -d)
        # Force C locale for consistent English output and apply TZ
        formatted_date=$(eval "${tz_prefix}LC_ALL=C date -d \"$input_date\" +\"$target_format\"" 2>/dev/null || echo "$input_date")
    fi

    echo "$formatted_date"
}

# Format a timestamp to a date string according to the configured DATE_FORMAT
format_date_from_timestamp() {
    local timestamp="$1"
    local format_override="$2" # Optional format string
    local target_format=${format_override:-"$DATE_FORMAT"} # Use override or global DATE_FORMAT
    local formatted_date

    # Skip formatting if timestamp is empty
    if [ -z "$timestamp" ]; then
        echo ""
        return
    fi

    # Set TZ environment variable if TIMEZONE is set and not "local"
    local tz_prefix=""
    if [ -n "${TIMEZONE:-}" ] && [ "${TIMEZONE:-local}" != "local" ]; then
        tz_prefix="TZ='${TIMEZONE}' "
    fi

    # Format the timestamp differently based on OS
    # IMPORTANT: DATE_FORMAT must be exported or sourced *before* calling this (for fallback)
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == *"bsd"* ]]; then
        # BSD systems (macOS, FreeBSD, etc.)
        # Force C locale for consistent English output and apply TZ
        formatted_date=$(eval "${tz_prefix}LC_ALL=C date -r \"$timestamp\" +\"$target_format\"" 2>/dev/null || echo "")
    else
        # Linux and other Unix-like systems
        # Force C locale for consistent English output and apply TZ
        formatted_date=$(eval "${tz_prefix}LC_ALL=C date -d \"@$timestamp\" +\"$target_format\"" 2>/dev/null || echo "")
    fi

    echo "$formatted_date"
}

# Generate a URL-friendly slug from a title
generate_slug() {
    local title="$1"

    # Convert to lowercase
    local slug=$(echo "$title" | tr '[:upper:]' '[:lower:]')

    # First use iconv to transliterate if available
    if command -v iconv >/dev/null 2>&1; then
        slug=$(echo "$slug" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || echo "$slug")
    fi

    # Replace all non-alphanumeric characters with hyphens
    slug=$(echo "$slug" | sed -e 's/[^a-z0-9]/-/g')

    # Replace multiple consecutive hyphens with a single one
    slug=$(echo "$slug" | sed -e 's/--*/-/g')

    # Remove leading and trailing hyphens
    slug=$(echo "$slug" | sed -e 's/^-//' -e 's/-$//')

    # If slug is empty, use 'untitled' as fallback
    if [ -z "$slug" ]; then
        slug="untitled"
    fi

    echo "$slug"
}

# File locking function
lock_file() {
    local file="$1"
    local lock_file="${file}.lock"
    local max_attempts=10
    local attempt=0

    # Try to create the lock file
    while [ $attempt -lt $max_attempts ]; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Successfully created the lock directory
            return 0
        fi

        # Wait before trying again
        sleep 0.1
        attempt=$((attempt + 1))
    done

    echo -e "${RED}Failed to acquire lock for $file after $max_attempts attempts${NC}"
    return 1
}

# Release the lock
unlock_file() {
    local file="$1"
    local lock_file="${file}.lock"

    # Remove the lock directory
    rmdir "$lock_file" 2>/dev/null || true
}

# Get file modification time in a portable way
get_file_mtime() {
    local file="$1"
    local kernel_name=$(uname -s)

    # Use specific stat flags based on kernel name
    # %m for BSD/macOS (seconds since Epoch)
    # %Y for Linux/GNU (seconds since Epoch)
    if [[ "$kernel_name" == "Darwin" ]] || [[ "$kernel_name" == *"BSD" ]]; then
        # BSD systems (macOS, FreeBSD, OpenBSD, NetBSD, etc.)
        stat -f "%m" "$file" 2>/dev/null || echo "0"
    else
        # Assume Linux/GNU stat
        stat -c "%Y" "$file" 2>/dev/null || echo "0"
    fi
}

# Fallback parallel implementation using background processes
# Used when GNU parallel is not available
run_parallel() {
    local max_jobs="$1"
    shift

    if [ -z "$max_jobs" ] || [ "$max_jobs" -lt 1 ]; then
        # Determine number of CPU cores if not specified
        if command -v nproc > /dev/null 2>&1; then
            # Linux
            max_jobs=$(nproc)
        elif command -v sysctl > /dev/null 2>&1; then
            # macOS, BSD
            max_jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        else
            # Default to 2 jobs if we can't determine
            max_jobs=2
        fi
    fi

    local job_count=0
    local pids=()

    # Read commands from stdin
    while read -r cmd; do
        # Skip empty lines
        [ -z "$cmd" ] && continue

        # If we've reached max jobs, wait for one to finish
        if [ $job_count -ge $max_jobs ]; then
            # Wait for any child process to finish
            wait -n 2>/dev/null || true

            # Cleanup finished jobs from pids array
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 $pid 2>/dev/null; then
                    new_pids+=($pid)
                fi
            done
            pids=("${new_pids[@]}")

            # Update job count
            job_count=${#pids[@]}
        fi

        # Run the command in the background
        (eval "$cmd") &
        pids+=($!)
        job_count=$((job_count + 1))
    done

    # Wait for all remaining jobs to finish
    wait
}

# Add a reading time calculation function
calculate_reading_time() {
    local content="$1"

    # Count words
    local word_count
    word_count=$(echo "$content" | wc -w | tr -d ' ')

    # Assuming average reading speed of 200 words per minute
    local reading_time_min=$((word_count / 200))

    # Ensure reading time is at least 1 minute
    if [ "$reading_time_min" -lt 1 ]; then
        reading_time_min=1
    fi

    echo "$reading_time_min"
}

# Export the functions
export -f format_date_from_timestamp
export -f generate_slug
export -f lock_file
export -f unlock_file
export -f get_file_mtime
export -f run_parallel
export -f calculate_reading_time
# Export the new print functions
export -f print_error
export -f print_warning
export -f print_success
export -f print_info 