#!/usr/bin/env bash
#
# BSSG - Dependency Checking
# Checks for required tools and sets up environment variables.
#

# Portable md5sum wrapper
portable_md5sum() {
    if command -v md5sum > /dev/null 2>&1; then
        # Linux: md5sum command exists
        md5sum "$@"
    elif [[ "$(uname)" == "OpenBSD" ]] || [[ "$(uname)" == "NetBSD" ]]; then
        # OpenBSD/NetBSD: md5 command without -r or -q
        # Output format: "MD5 (filename) = hash" -> Need "hash  filename"
        if [ $# -eq 0 ] || [ "$1" = "-" ]; then
            # Handle stdin: OpenBSD md5 outputs just the hash directly.
            # Read the hash (field 1) and append "  -" to match md5sum format.
            md5 | awk '{print $1 "  -"}'
        else
            # Handle files: MD5 (file) = hash -> hash  file
            md5 "$@" | awk '{print $4 "  " $2}' | sed 's/[()]//g'
        fi
    elif command -v md5 > /dev/null 2>&1; then
         # macOS / FreeBSD: Use md5 -r which outputs "hash filename"
         # This matches the old script's alias logic for macOS
         md5 -r "$@"
    else
        echo -e "${RED}Error: Neither md5sum nor md5 command found.${NC}" >&2
        return 1
    fi
}

# Check for required tools
check_dependencies() {
    local missing_deps=0

    # Array of required commands
    local deps=("awk" "sed" "grep" "find" "date")

    # Check if a usable MD5 command exists (md5sum or md5)
    if ! command -v md5sum &> /dev/null && ! command -v md5 &> /dev/null; then
         echo -e "${RED}Error: Neither 'md5sum' nor 'md5' command found. Cannot calculate checksums.${NC}"
         missing_deps=1
    # No need to add md5sum/md5 to the deps array, as we've already verified one exists
    fi

    # Add markdown processor dependency based on configuration
    # IMPORTANT: Config variables like MARKDOWN_PROCESSOR must be exported/available
    if [ "${MARKDOWN_PROCESSOR:-pandoc}" = "pandoc" ]; then # Default to pandoc if unset
        deps+=("pandoc")
    elif [ "$MARKDOWN_PROCESSOR" = "commonmark" ]; then
        # Check if cmark (commonmark implementation) is installed
        if ! command -v cmark &> /dev/null; then
            echo -e "${RED}Error: commonmark (cmark) is not installed${NC}"
            echo -e "${YELLOW}Tip: Install commonmark/cmark from https://github.com/commonmark/cmark${NC}"
            missing_deps=1
        fi
        # Add cmark even if missing, so the main loop reports it
        deps+=("cmark")
    elif [ "$MARKDOWN_PROCESSOR" = "markdown.pl" ]; then
        # Check if markdown.pl or Markdown.pl exists in PATH or current directory
        if command -v markdown.pl &> /dev/null; then
            MARKDOWN_PL_PATH="markdown.pl"
        elif command -v Markdown.pl &> /dev/null; then
            MARKDOWN_PL_PATH="Markdown.pl"
        elif [ -f "./markdown.pl" ] && [ -x "./markdown.pl" ]; then
            MARKDOWN_PL_PATH="./markdown.pl"
        elif [ -f "./Markdown.pl" ] && [ -x "./Markdown.pl" ]; then
            MARKDOWN_PL_PATH="./Markdown.pl"
        else
            echo -e "${RED}Error: markdown.pl is not installed or not in PATH${NC}"
            echo -e "${YELLOW}Tip: You can place markdown.pl in the BSSG directory and make it executable${NC}"
            missing_deps=1
        fi
        # Add the specific path if found, otherwise add the generic name for error reporting
        deps+=("${MARKDOWN_PL_PATH:-markdown.pl}")
    else
        echo -e "${RED}Error: Invalid MARKDOWN_PROCESSOR value ('$MARKDOWN_PROCESSOR'). Use 'pandoc', 'commonmark', or 'markdown.pl'.${NC}"
        # No dependency to add, but set missing_deps
        missing_deps=1
    fi

    echo "Checking dependencies..."

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            # Avoid redundant error for cmark/markdown.pl already printed
            if [[ "$dep" != "cmark" && "$dep" != "markdown.pl" && "$dep" != "./markdown.pl" && "$dep" != "./Markdown.pl" ]]; then
                 echo -e "${RED}Error: Required command '$dep' is not installed${NC}"
                 missing_deps=1
            fi
        fi
    done

    # Check for GNU parallel
    if [[ "$(uname)" == "NetBSD" ]]; then
        echo -e "${YELLOW}Parallel processing is unreliable on NetBSD. Using sequential processing.${NC}"
        export HAS_PARALLEL=false
    elif command -v parallel > /dev/null 2>&1 && { read -r _version < <(parallel -V 2>/dev/null ) && [[ "${_version:0:3}" = "GNU" ]]; }; then
        echo -e "${GREEN}GNU parallel found! Using parallel processing.${NC}"
        export HAS_PARALLEL=true
    else
        echo -e "${YELLOW}GNU parallel not found. Using sequential processing.${NC}"
        export HAS_PARALLEL=false
    fi

    if [ $missing_deps -eq 1 ]; then
        echo -e "${RED}Please install the missing dependencies and try again.${NC}"
        exit 1
    fi

    echo -e "${GREEN}All dependencies satisfied!${NC}"

    # Call directory check after dependency check
    check_directories || { echo -e "${RED}Error: Directory check failed.${NC}"; exit 1; }
}

# Check if src, templates directories exist and create output directory
check_directories() {
    echo "Checking required directories..."
    if [ ! -d "$SRC_DIR" ]; then
        echo -e "${RED}Error: Source directory '$SRC_DIR' does not exist${NC}"
        exit 1
    fi

    if [ ! -d "$TEMPLATES_DIR" ]; then
        echo -e "${RED}Error: Templates directory '$TEMPLATES_DIR' does not exist${NC}"
        exit 1
    fi

    if [ ! -d "$THEMES_DIR" ]; then
        echo -e "${RED}Error: Themes directory '$THEMES_DIR' does not exist${NC}"
        exit 1
    fi

    # Note: Output directory and cache directory creation is handled in main.sh initial setup.
    # We just check the source/template dirs here.

    echo -e "${GREEN}Source/Template/Theme directories verified!${NC}"
}

# Export functions
export -f check_dependencies
export -f check_directories
export -f portable_md5sum

# Define and export the MD5 command variable to use the portable function
MD5_CMD="portable_md5sum"
export MD5_CMD 