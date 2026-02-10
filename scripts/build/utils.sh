#!/usr/bin/env bash
#
# BSSG - Build Utilities
# Common functions and variables used across build scripts.
#

# Colors for output messages
if [[ -t 1 ]] && [[ -z $NO_COLOR ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# Cache kernel name once to avoid repeated `uname` calls in hot paths.
if [ -z "${BSSG_KERNEL_NAME:-}" ]; then
    BSSG_KERNEL_NAME="$(uname -s 2>/dev/null || echo "")"
fi

# Cache repeated date formatting work across stages in the same process.
declare -gA BSSG_FORMAT_DATE_CACHE=()
declare -gA BSSG_FORMAT_DATE_TS_CACHE=()

# GNU parallel workers import functions, but array declarations may not carry over.
# Keep date caches associative in every process to avoid bad-subscript errors.
_bssg_ensure_assoc_cache() {
    local var_name="$1"
    local var_decl

    var_decl=$(declare -p "$var_name" 2>/dev/null || true)
    if [[ "$var_decl" == declare\ -A* ]]; then
        return 0
    fi

    unset "$var_name" 2>/dev/null || true
    declare -gA "$var_name"
    eval "$var_name=()"
}

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
    local kernel_name="${BSSG_KERNEL_NAME:-}"
    if [ -z "$kernel_name" ]; then
        kernel_name="$(uname -s)"
    fi

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

    _bssg_ensure_assoc_cache "BSSG_FORMAT_DATE_CACHE"

    # Use cached values for stable (non-"now") inputs.
    local cache_tz="${TIMEZONE:-local}"
    local cache_key="${cache_tz}|${target_format}|${input_date}"
    if [[ -n "${BSSG_FORMAT_DATE_CACHE[$cache_key]+_}" ]]; then
        echo "${BSSG_FORMAT_DATE_CACHE[$cache_key]}"
        return
    fi

    # Try to format the date using the configured format
    # IMPORTANT: DATE_FORMAT must be exported or sourced *before* calling this
    if [[ "$kernel_name" == "Darwin" ]] || [[ "$kernel_name" == *"BSD" ]]; then
        # macOS/BSD date formatting (uses date -j -f)
        # Fast-path common stable inputs to avoid multiple failed parse attempts.
        if [[ "$input_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            formatted_date=$(eval "${tz_prefix}LC_ALL=C date -j -f \"%Y-%m-%d\" \"$input_date\" +\"$target_format\"" 2>/dev/null)
        elif [[ "$input_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
            formatted_date=$(eval "${tz_prefix}LC_ALL=C date -j -f \"%Y-%m-%d %H:%M:%S\" \"$input_date\" +\"$target_format\"" 2>/dev/null)
        elif [[ "$input_date" =~ ^[A-Za-z]{3},[[:space:]][0-9]{2}[[:space:]][A-Za-z]{3}[[:space:]][0-9]{4}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]][+-][0-9]{4}$ ]]; then
            formatted_date=$(eval "${tz_prefix}LC_ALL=C date -j -f \"%a, %d %b %Y %H:%M:%S %z\" \"$input_date\" +\"$target_format\"" 2>/dev/null)
        fi

        # Fallback parser chain for uncommon/legacy input variants.
        if [ -z "$formatted_date" ]; then
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

    BSSG_FORMAT_DATE_CACHE["$cache_key"]="$formatted_date"
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

    _bssg_ensure_assoc_cache "BSSG_FORMAT_DATE_TS_CACHE"

    # Cache by timestamp/format/timezone.
    local cache_tz="${TIMEZONE:-local}"
    local cache_key="${cache_tz}|${target_format}|${timestamp}"
    if [[ -n "${BSSG_FORMAT_DATE_TS_CACHE[$cache_key]+_}" ]]; then
        echo "${BSSG_FORMAT_DATE_TS_CACHE[$cache_key]}"
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

    BSSG_FORMAT_DATE_TS_CACHE["$cache_key"]="$formatted_date"
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
    local kernel_name="${BSSG_KERNEL_NAME:-}"

    # In RAM mode, prefer preloaded input timestamps.
    if [ "${BSSG_RAM_MODE:-false}" = true ] && declare -F ram_mode_get_mtime > /dev/null; then
        local ram_mtime
        ram_mtime=$(ram_mode_get_mtime "$file")
        if [ -n "$ram_mtime" ] && [ "$ram_mtime" != "0" ]; then
            echo "$ram_mtime"
            return 0
        fi
    fi

    if [ -z "$kernel_name" ]; then
        kernel_name="$(uname -s)"
    fi

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
detect_cpu_cores() {
    if command -v nproc > /dev/null 2>&1; then
        nproc
    elif command -v sysctl > /dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || echo 1
    else
        echo 2
    fi
}

# Determine worker count.
# In RAM mode we cap concurrency by default to reduce memory pressure from
# large inherited in-memory arrays in each worker process.
get_parallel_jobs() {
    local requested_jobs="$1"
    local jobs=0

    if [[ "$requested_jobs" =~ ^[0-9]+$ ]] && [ "$requested_jobs" -gt 0 ]; then
        jobs="$requested_jobs"
    else
        jobs=$(detect_cpu_cores)
    fi

    if [ "${BSSG_RAM_MODE:-false}" = true ]; then
        local ram_cap="${RAM_MODE_MAX_JOBS:-6}"
        if ! [[ "$ram_cap" =~ ^[0-9]+$ ]] || [ "$ram_cap" -lt 1 ]; then
            ram_cap=6
        fi
        if [ "$jobs" -gt "$ram_cap" ]; then
            jobs="$ram_cap"
        fi
    fi

    if [ "$jobs" -lt 1 ]; then
        jobs=1
    fi

    echo "$jobs"
}

run_parallel() {
    local max_jobs="$1"
    shift

    max_jobs=$(get_parallel_jobs "$max_jobs")

    local had_error=0
    local wait_n_supported=0
    if [[ ${BASH_VERSINFO[0]:-0} -gt 4 ]] || { [[ ${BASH_VERSINFO[0]:-0} -eq 4 ]] && [[ ${BASH_VERSINFO[1]:-0} -ge 3 ]]; }; then
        wait_n_supported=1
    fi

    if [ "$wait_n_supported" -eq 1 ]; then
        local running_jobs=0

        while read -r cmd; do
            [ -z "$cmd" ] && continue

            while [ "$running_jobs" -ge "$max_jobs" ]; do
                if ! wait -n 2>/dev/null; then
                    had_error=1
                fi
                running_jobs=$((running_jobs - 1))
            done

            (eval "$cmd") &
            running_jobs=$((running_jobs + 1))
        done

        while [ "$running_jobs" -gt 0 ]; do
            if ! wait -n 2>/dev/null; then
                had_error=1
            fi
            running_jobs=$((running_jobs - 1))
        done
    else
        # Portable fallback for older bash without wait -n.
        local pids=()
        while read -r cmd; do
            [ -z "$cmd" ] && continue

            while [ "${#pids[@]}" -ge "$max_jobs" ]; do
                local oldest_pid="${pids[0]}"
                if ! wait "$oldest_pid"; then
                    had_error=1
                fi
                pids=("${pids[@]:1}")
            done

            (eval "$cmd") &
            pids+=($!)
        done

        local pid
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                had_error=1
            fi
        done
    fi

    return "$had_error"
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

# Function to escape special characters for HTML
# Handles &, <, >, ", '
html_escape() {
    # Use Perl for efficient substitution if available
    if command -v perl > /dev/null 2>&1; then
        echo "$1" | perl -pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g; s/"/&quot;/g; s/\x27/&apos;/g;'
    else
        # Fallback to sed (might be slower for many calls)
        echo "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/&apos;/g"
    fi
}

# Export the functions
export -f format_date_from_timestamp
export -f generate_slug
export -f lock_file
export -f unlock_file
export -f get_file_mtime
export -f detect_cpu_cores
export -f get_parallel_jobs
export -f run_parallel
export -f calculate_reading_time
export -f html_escape
# Export the new print functions
export -f print_error
export -f print_warning
export -f print_success
export -f print_info
export -f _bssg_ensure_assoc_cache
