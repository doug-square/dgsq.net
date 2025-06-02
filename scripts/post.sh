#!/usr/bin/env bash
#
# BSSG - Post Creation Script
# Create and manage blog posts
#
# Developed by Stefano Marinelli (stefano@dragas.it)
# Project Homepage: https://bssg.dragas.net
#

set -e

# Load configuration (DEPRECATED - Handled centrally by bssg.sh sourcing config_loader.sh)
# CONFIG_FILE="config.sh"
# if [ -f "$CONFIG_FILE" ]; then
#     source "$CONFIG_FILE"
# else
#     echo "Error: Configuration file '$CONFIG_FILE' not found"
#     exit 1
# fi

# Load local configuration overrides if they exist (DEPRECATED - Handled centrally)
# LOCAL_CONFIG_FILE="config.sh.local"
# if [ -f "$LOCAL_CONFIG_FILE" ]; then
#     source "$LOCAL_CONFIG_FILE"
# fi

# Terminal colors (DEPRECATED - Handled centrally by config_loader.sh)
# RED='${RED:-\\033[0;31m}'
# GREEN='${GREEN:-\\033[0;32m}'
# YELLOW='${YELLOW:-\\033[0;33m}'
# NC='${NC:-\\033[0m}' # No Color

# Flag to track if vi is used as fallback
VI_FALLBACK=false

# Check if EDITOR is set, otherwise default to nano or vi
# Use inherited color variables (e.g. $YELLOW, $NC)
if [ -z "$EDITOR" ]; then
    if command -v nano &> /dev/null; then
        echo -e "${YELLOW}EDITOR environment variable not set. Using nano as default.${NC}" # Now uses inherited vars
        EDITOR="nano"
    elif command -v vi &> /dev/null; then
        echo -e "${YELLOW}EDITOR environment variable not set and nano not found. Using vi as default.${NC}" # Now uses inherited vars
        EDITOR="vi"
        VI_FALLBACK=true
    else
        echo -e "${RED}Error: EDITOR environment variable not set, and neither nano nor vi could be found.${NC}" # Now uses inherited vars
        exit 1
    fi
fi

# Generate a URL-friendly slug from a title
# This implementation matches the one in scripts/build/utils.sh
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

# Function to display usage information
usage() {
    echo "Usage: $0 [options] | [draft_file]"
    echo ""
    echo "Creates a new post."
    echo ""
    echo "Interactive Mode (Default):"
    echo "  $0                 Start interactive post creation."
    echo "  $0 <draft_file>    Continue editing a draft file interactively."
    echo "  $0 -html           Start interactive post creation in HTML format."
    echo ""
    echo "Command-Line Mode:"
    echo "  Options:"
    echo "    -t <title>       Specify the post title (required)."
    echo "    -T <tags>        Specify comma-separated tags."
    echo "    -c <content>     Provide post content directly as a string."
    echo "    -f <file>        Read post content from the specified file."
    echo "    --stdin          Read post content from standard input."
    echo "    -s <slug>        Specify the slug (generated from title if omitted)."
    echo "    --html           Create the post in HTML format (default is Markdown)."
    echo "    -d, --draft      Save the post as a draft in '$DRAFTS_DIR'."
    echo "    --build          Force a site build after creating the post, even if REBUILD_AFTER_POST is false."
    echo ""
    echo "  Notes:"
    echo "    - Exactly one of -c, -f, or --stdin must be provided for content."
    echo "    - If using command-line mode, do not provide a draft_file argument."
    exit 1
}

# Function for interactive post creation
interactive_post() {
    local html_mode=false
    local draft_mode=false
    local draft_file=""

    # Parse arguments for interactive mode
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -html|--html)
                html_mode=true
                shift
                ;;
            -d|--draft)
                draft_mode=true # Though handled globally now, keep for potential future interactive use
                shift
                ;;
            *)
                # Assume it's a draft file if it exists
                if [ -f "$1" ] && [[ "$1" == *"$DRAFTS_DIR"* ]]; then
                    draft_file="$1"
                elif [ -n "$1" ]; then
                     echo -e "${YELLOW}Warning: Argument '$1' ignored in interactive mode unless it's an existing draft file.${NC}"
                fi
                shift
                ;;
        esac
    done

    # Create drafts directory if it doesn't exist
    mkdir -p "$DRAFTS_DIR"

    # If a draft file is specified, edit it
    if [ -n "$draft_file" ]; then
        echo "Editing existing draft: $draft_file"
        edit_file "$draft_file"
        exit 0
    fi

    # Get post title
    echo -e "${YELLOW}Enter post title:${NC}"
    read -r title

    if [ -z "$title" ]; then
        echo -e "${RED}Error: Title cannot be empty${NC}"
        exit 1
    fi

    # Generate slug
    local slug
    slug=$(generate_slug "$title")

    # Get current date
    local date_now
    date_now=$(date +%Y-%m-%d-%H-%M-%S) # Used for filename timestamp if needed

    # Format date for display and metadata (keeping time with timezone)
    local display_date
    display_date=$(date "+%Y-%m-%d %H:%M:%S %z")

    # Create filename - use date without time for filename to keep it cleaner
    local filename_base
    filename_base="$(echo "$date_now" | cut -d'-' -f1-3)-$slug"

    local filename
    if [ "$html_mode" = true ]; then
        filename="$filename_base.html"
    else
        filename="$filename_base.md"
    fi

    local output_path
    # Draft mode for interactive is less common, but possible
    # The main script logic handles the -d/--draft flag positioning
    if [ "$IS_DRAFT" = true ]; then
        output_path="$DRAFTS_DIR/$filename"
        echo "Saving as draft: $output_path"
    else
        output_path="$SRC_DIR/$filename"
        echo "Saving post: $output_path"
    fi

    # Check if file already exists
    if [ -f "$output_path" ]; then
        echo -e "${RED}Error: File '$output_path' already exists${NC}"
        exit 1
    fi

    # Define the vi easter egg message with actual newlines
    local vi_message=$(cat <<-EOM
Looks like you're using vi because nano wasn't around. Don't panic!
To save and exit: Press Esc, then type :wq and press Enter.
To exit without saving: Press Esc, then type :q! and press Enter.
Good luck!

EOM
    )

    # Create template based on format
    if [ "$html_mode" = true ]; then
        local initial_content="<p>Your content here...</p>"
        if [ "$VI_FALLBACK" = true ]; then
             # Embed the message directly within pre tags
            initial_content="<pre>${vi_message}</pre>"
        fi
        cat > "$output_path" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$title</title>
    <meta name="tags" content="">
    <meta name="date" content="$display_date">
    <meta name="lastmod" content="$display_date">
    <meta name="slug" content="$slug">
    <meta name="author_name" content="">
    <meta name="author_email" content="">
</head>
<body>
    <h1>$title</h1>
    $initial_content
</body>
</html>
EOF
    else
        local initial_content="Your content here..."
        if [ "$VI_FALLBACK" = true ]; then
            # Assign the message directly
            initial_content="$vi_message"
        fi
        cat > "$output_path" << EOF
---
title: $title
date: $display_date
lastmod: $display_date
tags:
slug: $slug
image:
image_caption:
description:
author_name:
author_email:
---

$initial_content
EOF
    fi

    # Open in editor
    edit_file "$output_path"

    # Build site if not a draft and REBUILD_AFTER_POST is true
    if [ "$IS_DRAFT" = false ] && [ "$REBUILD_AFTER_POST" = true ]; then
        echo "Building the site (REBUILD_AFTER_POST=true)..."
        if ! "$BSSG_SCRIPT_DIR/scripts/build/main.sh"; then
            echo -e "${RED}Error: Failed to build the site after creating the post.${NC}" >&2
            # Consider if we should exit here or just warn
            exit 1 # Exit on build failure after interactive post
        fi
        echo -e "${GREEN}Post '$title' created successfully and site rebuilt.${NC}"
    elif [ "$IS_DRAFT" = false ]; then
        echo -e "${GREEN}Post '$title' created successfully. Rebuild skipped (REBUILD_AFTER_POST=false).${NC}"
    else
        echo -e "${GREEN}Draft '$title' saved successfully in interactive mode.${NC}" # Message for draft saving
    fi
}

# Function to edit a file
edit_file() {
    local file="$1"

    if ! "$EDITOR" "$file"; then
       echo -e "${RED}Error: Editor '$EDITOR' failed or exited with non-zero status while editing '$file'.${NC}" >&2
       # Decide if this should be a fatal error. Usually yes.
       exit 1
    fi

    # Check if the file is empty or contains only whitespace after editing
    # This can happen if the user quits the editor without saving or saves an empty file
    if [ ! -s "$file" ] || ! grep -q '[^[:space:]]' "$file"; then
        echo -e "${YELLOW}Warning: File '$file' appears empty or contains only whitespace after editing.${NC}" >&2
        # Ask the user if they want to keep the empty file or delete it?
        # For now, we'll keep it, but this could be enhanced.
    fi

    echo -e "${GREEN}File editing session finished for: $file${NC}"
}

# --- Main Script Logic ---

# Define variables for command-line arguments
POST_TITLE=""
POST_TAGS=""
POST_CONTENT=""
CONTENT_FILE=""
USE_STDIN=false
POST_SLUG=""
HTML_MODE=false
IS_DRAFT=false
INTERACTIVE_MODE=true # Assume interactive unless command-line args are found
DRAFT_FILE_ARG="" # To capture potential draft file argument
FORCE_BUILD=false # Flag to force build via command line

# Simple argument parsing loop (more portable than getopts for long options)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t)
            POST_TITLE="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -T)
            POST_TAGS="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -c)
            POST_CONTENT="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -f)
            CONTENT_FILE="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        --stdin)
            USE_STDIN=true
            INTERACTIVE_MODE=false
            shift 1
            ;;
        -s)
            POST_SLUG="$2"
            INTERACTIVE_MODE=false
            shift 2
            ;;
        -d|--draft)
            IS_DRAFT=true
            # Don't set interactive_mode=false here, draft can be used with interactive
            shift 1
            ;;
        -html|--html)
            HTML_MODE=true
            # Don't set interactive_mode=false here, html can be used with interactive
            shift 1
            ;;
        -h|--help)
            usage
            ;;
        --build)
            FORCE_BUILD=true
            INTERACTIVE_MODE=false # Implies command-line mode
            shift 1
            ;;
        *)
            # If it's not an option, assume it could be a draft file for interactive mode
            # Check if it looks like an option first
            if [[ "$1" == -* ]]; then
                 echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
                 usage
            fi
             # Check if it's a file that exists (could be a draft)
             if [ -f "$1" ]; then
                 DRAFT_FILE_ARG="$1"
                 # If a draft file is given, it implies interactive mode or editing an existing draft.
                 # Let the interactive_post function handle it.
                 INTERACTIVE_MODE=true
             else
                 # It's not a file and not an option we recognize in non-interactive mode
                 if [ "$INTERACTIVE_MODE" = false ]; then
                    echo -e "${RED}Error: Unexpected argument '$1' in command-line mode.${NC}" >&2
                    usage
                 fi
                 # If still in potential interactive mode, let interactive_post decide later
             fi
            shift 1
            ;;
    esac
done

# --- Execute based on mode ---

if [ "$INTERACTIVE_MODE" = true ]; then
    # Pass relevant flags and potential draft file to interactive mode
    interactive_args=()
    if [ "$HTML_MODE" = true ]; then interactive_args+=("--html"); fi
    # IS_DRAFT is handled globally, no need to pass -d
    if [ -n "$DRAFT_FILE_ARG" ]; then interactive_args+=("$DRAFT_FILE_ARG"); fi

    echo "Starting interactive post creation..."
    interactive_post "${interactive_args[@]}"
else
    # --- Non-Interactive (Command-Line) Mode ---
    echo "Running in command-line mode..."

    # Validate arguments
    if [ -z "$POST_TITLE" ]; then
        echo -e "${RED}Error: Title (-t) is required for command-line posting.${NC}" >&2
        usage
    fi

    content_sources=0
    if [ -n "$POST_CONTENT" ]; then content_sources=$((content_sources + 1)); fi
    if [ -n "$CONTENT_FILE" ]; then content_sources=$((content_sources + 1)); fi
    if [ "$USE_STDIN" = true ]; then content_sources=$((content_sources + 1)); fi

    if [ "$content_sources" -ne 1 ]; then
        echo -e "${RED}Error: Exactly one content source (-c, -f, or --stdin) must be provided.${NC}" >&2
        usage
    fi

    # Read content
    if [ -n "$CONTENT_FILE" ]; then
        if [ ! -f "$CONTENT_FILE" ]; then
            echo -e "${RED}Error: Content file '$CONTENT_FILE' not found.${NC}" >&2
            exit 1
        fi
        POST_CONTENT=$(cat "$CONTENT_FILE")
    elif [ "$USE_STDIN" = true ]; then
        echo "Reading content from stdin..."
        POST_CONTENT=$(cat)
    # else content is already in $POST_CONTENT from -c
    fi

    # Get date and slug
    date_now=$(date +%Y-%m-%d-%H-%M-%S)
    display_date=$(date "+%Y-%m-%d %H:%M:%S %z")
    if [ -z "$POST_SLUG" ]; then
        POST_SLUG=$(generate_slug "$POST_TITLE")
    fi

    # Determine filename and path
    filename_base="$(echo "$date_now" | cut -d'-' -f1-3)-$POST_SLUG"
    file_ext=".md"
    if [ "$HTML_MODE" = true ]; then
        file_ext=".html"
    fi
    filename="$filename_base$file_ext"

    output_dir="$SRC_DIR"
    if [ "$IS_DRAFT" = true ]; then
        output_dir="$DRAFTS_DIR"
        mkdir -p "$output_dir" # Ensure draft dir exists
    fi
    output_path="$output_dir/$filename"

    # Check if file already exists
    if [ -f "$output_path" ]; then
        echo -e "${RED}Error: File '$output_path' already exists.${NC}" >&2
        exit 1
    fi

    echo "Creating post: $output_path"

    # Create post file content
    if [ "$HTML_MODE" = true ]; then
        # Simple HTML structure
        cat > "$output_path" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$POST_TITLE</title>
    <meta name="tags" content="$POST_TAGS">
    <meta name="date" content="$display_date">
    <meta name="lastmod" content="$display_date">
    <meta name="slug" content="$POST_SLUG">
    <meta name="author_name" content="">
    <meta name="author_email" content="">
</head>
<body>
    <h1>$POST_TITLE</h1>
    $POST_CONTENT
</body>
</html>
EOF
    else
        # Markdown with front matter
        cat > "$output_path" << EOF
---
title: $POST_TITLE
date: $display_date
lastmod: $display_date
tags: $POST_TAGS
slug: $POST_SLUG
image:
image_caption:
description:
author_name:
author_email:
---

$POST_CONTENT
EOF
    fi

    echo -e "${GREEN}Successfully created post: $output_path${NC}"

    # Build site if not a draft and (REBUILD_AFTER_POST is true OR --build flag is set)
    if [ "$IS_DRAFT" = false ] && { [ "$REBUILD_AFTER_POST" = true ] || [ "$FORCE_BUILD" = true ]; }; then
        echo "Building the site (REBUILD_AFTER_POST=$REBUILD_AFTER_POST, FORCE_BUILD=$FORCE_BUILD)..."
        # Assuming bssg.sh is in the parent directory of scripts/
        BSSG_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
        if ! "$BSSG_SCRIPT_DIR/scripts/build/main.sh"; then
            echo -e "${RED}Error: Failed to build the site after creating the post.${NC}" >&2
            # Exit non-zero on build failure after command-line post
            exit 1
        fi
        echo -e "${GREEN}Site rebuilt successfully.${NC}"
    elif [ "$IS_DRAFT" = false ] && [ "$REBUILD_AFTER_POST" = false ] && [ "$FORCE_BUILD" = false ]; then
         echo -e "${YELLOW}Rebuild skipped (REBUILD_AFTER_POST=false and --build not specified).${NC}"
    else
         echo -e "${GREEN}Draft saved successfully.${NC}"
    fi

fi

exit 0

# --- Original create_post function (now integrated/refactored) ---
# create_post() { ... original content moved ... }
# --- Original main execution (now replaced) ---
# create_post "$@"
