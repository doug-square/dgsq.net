#!/usr/bin/env bash
#
# BSSG - Configuration File
# Version 0.15
# Contains all configurable parameters for the static site generator
# Developed by Stefano Marinelli (stefano@dragas.it)
#
# =======================================================================
# IMPORTANT: DO NOT MODIFY THIS FILE DIRECTLY
# For local configuration changes, create config.sh.local with your 
# custom settings. Those settings will override the ones in this file.
# This file is part of the git repository and your changes may be lost.
# =======================================================================

# Directory configuration
SRC_DIR="src"
PAGES_DIR="pages"  # Directory for static pages
OUTPUT_DIR="output"
TEMPLATES_DIR="templates"
THEMES_DIR="themes"
STATIC_DIR="static"
DRAFTS_DIR="drafts" # Directory for drafts
THEME="default"

# Build configuration
CLEAN_OUTPUT=false # If true, BSSG will always perform a full rebuild
REBUILD_AFTER_POST=true # Build site automatically after creating a new post (scripts/post.sh)
REBUILD_AFTER_EDIT=true # Build site automatically after editing a post (scripts/edit.sh)

# Customization
CUSTOM_CSS="" # Optional: Path to custom CSS file relative to output root (e.g., "/css/custom.css"). File should be placed in STATIC_DIR.

# Site information
SITE_TITLE="My new BSSG site"
SITE_DESCRIPTION="A complete SSG - written in bash"
SITE_URL="http://localhost:8000"
AUTHOR_NAME="Anonymous" 
AUTHOR_EMAIL="anonymous@example.com"

# Content configuration
DATE_FORMAT="%Y-%m-%d %H:%M:%S %z"
TIMEZONE="local"  # Options: "local", "GMT", or a specific timezone like "America/New_York"
SHOW_TIMEZONE="false" # Options: "true", "false". Whether to display the timezone in rendered dates.
POSTS_PER_PAGE=10
RSS_ITEM_LIMIT=15 # Number of items to include in the RSS feed.
RSS_INCLUDE_FULL_CONTENT="false" # Options: "true", "false". Include full post content in RSS feed.
ENABLE_ARCHIVES=true  # Enable or disable archive pages
URL_SLUG_FORMAT="Year/Month/Day/slug"  # Format for post URLs: Year/Month/Day/slug will create Year/Month/Day/slug/index.html
ENABLE_TAG_RSS=true # Enable or disable tag-specific RSS feed generation (default: true)

# Page configuration
PAGE_URL_FORMAT="pages/slug"  # Format for page URLs: pages/slug will create pages/slug/index.html

# Markdown processing configuration
MARKDOWN_PROCESSOR="commonmark" # Options: "pandoc", "commonmark", or "markdown.pl"

# Language Configuration
SITE_LANG="en"  # Default language code (e.g., en, es, fr). See locales/ directory.

# Deployment configuration
DEPLOY_AFTER_BUILD="false" # Options: "true", "false". Automatically deploy after a successful build.
DEPLOY_SCRIPT=""           # Path to the deployment script to execute if DEPLOY_AFTER_BUILD is true.

# Terminal colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color 
