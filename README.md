# BSSG - Bash Static Site Generator

[BSSG](https://bssg.dragas.net) is a simple static site generator written in Bash. It processes Markdown files and builds a minimal, accessible website suitable for personal journals, daily writing, or introspective personal newspapers.

## Table of Contents
- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Recommended Setup: Separating Content from Core](#recommended-setup-separating-content-from-core)
- [Directory Structure](#directory-structure)
- [Usage](#usage)
- [Markdown Post Format](#markdown-post-format)
- [Customization](#customization)
- [Themes](#themes)
- [Theme Previews](#theme-previews)
- [Admin Interface](#admin-interface)
- [Performance Features](#performance-features)
- [Site Configuration](#site-configuration)
- [Future Plans](#future-plans)
- [Troubleshooting](#troubleshooting)
- [Author and License](#author-and-license)
- [Documentation](#documentation)

## Features

- Generates HTML from Markdown using pandoc, commonmark, or markdown.pl (configurable)
- Supports post metadata (title, date, tags)
- Supports `lastmod` timestamp in frontmatter for tracking content updates (used in sitemap, RSS feed, and optionally displayed on posts).
- Full date and time support with timezone awareness
- Post descriptions/summaries for previews, OpenGraph, and RSS
- Admin interface for managing posts and scheduling publications
- Creates tag index pages
- Archives by year and month for chronological browsing
- Dynamic menu generation based on available pages
- Support for primary and secondary pages with automatic menu organization
- Generates sitemap.xml and RSS feed with timezone support
- Clean design
- No JavaScript required (except for admin interface)
- Works well without images
- Cross-platform (Linux, macOS, BSDs)
- Reading time calculation for posts
- Pagination for blog posts with configurable posts per page
- Multiple themes available (see [Themes section](#themes))
- Theme preview generator to see all available themes in action
- Supports static files (images, CSS, JS, etc.)
- Configurable clean output directory option
- Draft posts support
- Post scheduling system
- Backup and restore functionality
- Incremental builds with file caching for improved performance
- Smart metadata caching system
- Parallel processing support using GNU parallel (if available)
- File locking for safe concurrent operations
- Automatic handling of different operating systems (Linux/macOS/BSDs)
- Custom URL slugs with SEO-friendly permalinks
- Featured images in posts are displayed in index, tag, and archive pages
- Support for static pages with custom URLs

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://brew.bsd.cafe/stefano/BSSG.git
   cd BSSG
   ```

2. Create your first post:
   ```bash
   ./bssg.sh post
   ```

3. Build the site:
   ```bash
   ./bssg.sh build
   ```
   *(This command now invokes the modular build process located in `scripts/build/`)*

4. View your site in the `output` directory or serve it locally:
   ```bash
   cd output
   python3 -m http.server 8000
   ```

5. Open your browser and navigate to http://localhost:8000

## Recommended Setup: Separating Content from Core

**Why separate?** This setup keeps your website's content (posts, pages, static files, configuration) in a dedicated directory, separate from the BSSG core scripts. This makes it much easier to update BSSG itself (using `git pull` in the core directory) without affecting or risking conflicts with your site content. This is the **recommended approach for most users**.

1.  **Clone BSSG Core (if you haven't already):**
    ```bash
    git clone https://brew.bsd.cafe/stefano/BSSG.git
    cd BSSG # Navigate into the BSSG core directory
    ```

2.  **Initialize Your Site Directory:**
    From within the BSSG core directory, run the `init` command, specifying the path where you want your new site's content to live:
    ```bash
    ./bssg.sh init /path/to/your/new/website
    ```
    *Replace `/path/to/your/new/website` with the actual path (e.g., `~/my-blog`, `./my-website`).*

3.  **Directory Structure Creation:**
    BSSG will create the necessary content directories (`src`, `pages`, `drafts`, `static`) inside `/path/to/your/new/website`. The build output (`output/`) will also be placed within this new site directory by default.

4.  **Site Configuration File:**
    A specific `config.sh.local` file will be automatically created *inside your new site directory* (`/path/to/your/new/website/config.sh.local`). This file tells BSSG where to find your content (`SRC_DIR`, `PAGES_DIR`, etc.) and where to build the output (`OUTPUT_DIR`).

5.  **Automatic Configuration Loading (Optional but Recommended):**
    The `init` script will ask if you want to modify the `config.sh.local` file located *within the BSSG core directory* to automatically point to your new site's configuration.
    *   **Choose `yes` (y):** This is the **recommended** option. It adds a line to the *core* `config.sh.local` that sources your *site's* configuration file. This means you can run `./bssg.sh` commands (like `build`, `post`, `page`) directly from the BSSG core directory, and it will automatically use the correct settings for your separated site. (Note: For reliability, the `source` command added to the core config will use the resolved absolute path to your site's configuration file, even if you provided a relative or tilde-prefixed path during `init`.)
    *   **Choose `no` (N):** If you choose no, you will need to manually specify your site's configuration file using the `--config` flag every time you run a BSSG command from the core directory that needs to know about your site:
        ```bash
        # Example: Running build from the BSSG core directory
        ./bssg.sh build --config /path/to/your/new/website/config.sh.local

        # Example: Creating a post from the BSSG core directory
        ./bssg.sh post --config /path/to/your/new/website/config.sh.local
        ```

**Benefit:** With your content separated, you can safely update the BSSG core scripts in their own directory using `git pull` without worrying about overwriting your posts, pages, or custom configurations.


## Requirements

BSSG requires the following tools:

- Bash
- pandoc, commonmark, or markdown.pl (configurable in config.sh.local)
- Standard Unix utilities (awk, sed, grep, find, date)

### Installation of Dependencies

#### On Debian/Ubuntu:
```bash
sudo apt-get update
sudo apt-get install cmark
```

#### On macOS (using Homebrew):
```bash
brew install bash cmark
```

#### On FreeBSD:
```bash
pkg install bash cmark
```

#### On OpenBSD:
```bash
pkg_add bash cmark 
```

#### On NetBSD:
```bash
pkgin in bash cmark
```

### Using markdown.pl instead of commonmark

If you prefer using markdown.pl instead of commonmark:

1. Set `MARKDOWN_PROCESSOR="markdown.pl"` in your `config.sh.local` file
2. Make sure markdown.pl is installed:
   - You can download it from [Daring Fireball](https://daringfireball.net/projects/markdown/)
   - Place it in your PATH or directly in the BSSG directory
   - Make it executable with `chmod +x markdown.pl`

BSSG will search for either `markdown.pl` or `Markdown.pl` (case-sensitive) in both your system PATH and the current BSSG directory.

### Using pandoc instead of commonmark

If you prefer using pandoc instead of commonmark:

1. Set `MARKDOWN_PROCESSOR="pandoc"` in your `config.sh.local` file
2. Make sure pandoc is installed:
   - On Debian/Ubuntu: `apt install pandoc`
   - On Fedora: `dnf install pandoc`
   - On macOS: `brew install pandoc`
   - On FreeBSD: `pkg install hs-pandoc`
   - On OpenBSD: `pkg_add pandoc`

Commonmark provides a stricter and more standardized Markdown implementation and is portable across different operating systems.

## Directory Structure

```
BSSG/
├── bssg.sh                        # Main command interface script
├── generate_theme_previews.sh     # Script to generate previews of all themes
├── scripts/                       # Supporting scripts
│   ├── build/                     # Modular build scripts
│   │   ├── main.sh                # Main build orchestrator
│   │   ├── utils.sh               # Utility functions (colors, formatting, etc.)
│   │   ├── cli.sh                 # Command-line argument parsing
│   │   ├── config_loader.sh       # Loads default and user configuration
│   │   ├── deps.sh                # Dependency checking
│   │   ├── cache.sh               # Cache management functions
│   │   ├── content_discovery.sh   # Finds posts, pages, drafts
│   │   ├── markdown_processor.sh  # Markdown conversion logic
│   │   ├── process_posts.sh       # Processes individual posts
│   │   ├── process_pages.sh       # Processes individual pages
│   │   ├── generate_indexes.sh    # Creates index, tag, and archive pages
│   │   ├── generate_feeds.sh      # Creates RSS feed and sitemap
│   │   ├── generate_secondary_pages.sh # Creates pages.html index
│   │   ├── copy_static.sh         # Copies static files and theme assets
│   │   └── theme_utils.sh         # Theme-related utilities
│   ├── post.sh                    # Handles post creation
│   ├── page.sh                    # Handles page creation
│   ├── edit.sh                    # Handles post/page editing (updates lastmod)
│   ├── delete.sh                  # Handles post/page/draft deletion
│   ├── list.sh                    # Lists posts, pages, drafts, tags
│   ├── backup.sh                  # Backup functionality
│   ├── restore.sh                 # Restore functionality
│   ├── theme.sh                   # Theme management and processing (legacy helper)
│   ├── template.sh                # Template processing utilities (legacy helper)
│   └── css.sh                     # CSS generation utilities (legacy helper)
├── src/                           # Source directory for markdown posts (Configurable: $SRC_DIR)
│   └── *.md                       # Markdown posts
├── pages/                         # Source directory for static pages (Configurable: $PAGES_DIR)
│   └── *.md                       # Markdown pages
├── drafts/                        # Source directory for drafts (Configurable: $DRAFTS_DIR)
│   ├── *.md/*.html                # Draft posts
│   └── pages/                     # Optional subdirectory for page drafts
│       └── *.md/*.html            # Draft pages
├── templates/                     # HTML templates (used by themes)
│   ├── header.html                # Header template
│   └── footer.html                # Footer template
├── themes/                        # Theme directory for different visual styles
│   ├── default/                   # Default theme
│   ├── dark/                      # Dark theme
│   └── ...                        # Other themes
├── static/                        # Static files to be copied to output directory
├── admin/                         # Admin interface files
├── example/                       # Theme preview directory (generated)
├── .bssg_cache/                   # Cache directory for improved performance
├── config.sh                      # Default site configuration
├── config.sh.local                # Optional user overrides for configuration
└── output/                        # Generated HTML website (created during build)
```

## Usage

### Basic Commands

```bash
cd BSSG
./bssg.sh [command] [options]
```

### Available Commands

```
Usage: ./bssg.sh command [options]

Commands:
  post [-html] [draft_file]    # Interactive: Create/edit post/draft, prompt for title, open editor.
                               # Rebuilds site afterwards if REBUILD_AFTER_POST=true in config.
                               # Use -html for HTML format.
  post -t <title> [-T <tags>] [-s <slug>] [--html] [-d] {-c <content> | -f <file> | --stdin} [--build]
                               # Command-line: Create post non-interactively.
                               #   -t: Title (required)
                               #   -T: Tags (comma-sep)
                               #   -s: Slug (optional)
                               #   --html: HTML format (default: MD)
                               #   -d: Save as draft
                               #   -c: Content string
                               #   -f: Content file
                               #   --stdin: Content from stdin
                               #   --build: Force rebuild (overrides REBUILD_AFTER_POST=false)
  page [-html] [-s] [draft_file] Create a new page (in $PAGES_DIR or $DRAFTS_DIR/pages)
                               or continue editing a draft (in $DRAFTS_DIR/pages)
                               Use -html to edit in HTML instead of Markdown
                               Use -s to mark page as secondary (for menu)
  edit [-n] <file>             Edit an existing post/page/draft (updates lastmod)
                               File path should point to $SRC_DIR, $PAGES_DIR, $DRAFTS_DIR etc.
                               Use -n to rename based on title (posts/drafts only currently)
  delete [-f] <file>           Delete a post/page/draft
                               File path should point to $SRC_DIR, $PAGES_DIR, $DRAFTS_DIR etc.
                               Use -f to skip confirmation
  list {posts|pages|drafts|tags [-n]}
                               List posts ($SRC_DIR), pages ($PAGES_DIR),
                               drafts ($DRAFTS_DIR and $DRAFTS_DIR/pages), or tags.
                               For tags, use -n to sort by count.
  backup                       Create a backup of all posts, pages, drafts, and config
  restore [backup_file|ID]     Restore from a backup (all content by default)
                               Options: --no-posts, --no-drafts, --no-pages, --no-config
  backups                      List all available backups
  build [opts]                 Build the site using the modular build system in scripts/build/
                               Options: -c|--clean-output, -f|--force-rebuild,
                                        --config FILE, --theme NAME,
                                        --site-url URL, --output DIR
  init <target_directory>      Initialize a new, empty site structure in the specified directory.
                               This is useful for separating your site content from the BSSG core scripts.
                               The script will preserve the path format you provide (relative, absolute, or tilde-prefixed)
                               in the generated site 'config.sh.local' for portability.
                               Note: If using '~' for your home directory, quote the path (e.g., '~/mysite' or "~/mysite")
                               to ensure the tilde is preserved in the generated config.
  help                         Show this help message
```

### Creating Posts and Pages

To create a new post interactively:

```bash
./bssg.sh post
```

To create a new page interactively:

```bash
./bssg.sh page
```

You'll be prompted for a title, and `$EDITOR` will open for you to write your content. By default, the site rebuilds automatically after saving an interactive post if `REBUILD_AFTER_POST` is set to `true` in your configuration (`config.sh` or `config.sh.local`).

To create a post non-interactively via the command line (see command list above for all options):

```bash
# Example: Create markdown post from file, force build
./bssg.sh post -t "My CLI Post" -f content.md --build

# Example: Create HTML post from stdin, don't force build (relies on REBUILD_AFTER_POST)
echo "<p>Hello</p>" | ./bssg.sh post -t "HTML Test" --html --stdin
```

To create a secondary page (appears under the "Pages" menu):

```bash
./bssg.sh page -s
```

Secondary pages will be listed under a "Pages" menu item in the navigation, which appears automatically when secondary pages exist.

#### Creating HTML Content

To create content in HTML format instead of Markdown:

```bash
./bssg.sh post -html  # For posts
./bssg.sh page -html  # For pages
```

Example of HTML content:

```html
---
title: HTML Example
date: 2023-01-15
tags: html, example
---

<h2>This is an HTML post</h2>
<p>You can use full HTML markup in this post.</p>
<ul>
    <li>Item 1</li>
    <li>Item 2</li>
</ul>
```

#### Working with Drafts

To save content as a draft (will not be published):

```bash
./bssg.sh post -d  # For posts
./bssg.sh page -d  # For pages
```

To continue editing a draft:

```bash
./bssg.sh post drafts/your-draft-file.md  # For posts
./bssg.sh page drafts/pages/your-draft-file.md  # For pages
```

To list all draft posts:

```bash
./bssg.sh drafts
```

### Editing and Deleting Posts

To edit an existing post:

```bash
./bssg.sh edit src/your-post-file.md
```

To rename the file when the title changes:

```bash
./bssg.sh edit -n src/your-post-file.md
```

To delete a post:

```bash
./bssg.sh delete src/your-post-file.md
```

### Listing Posts and Tags

To list all posts:

```bash
./bssg.sh list
```

To list all tags:

```bash
./bssg.sh tags
```

To list tags sorted by number of posts:

```bash
./bssg.sh tags -n
```

### Backup and Restore

To create a backup of all posts:

```bash
./bssg.sh backup
```

To list available backups:

```bash
./bssg.sh backups
```

To restore from a backup (will prompt for confirmation):

```bash
./bssg.sh restore [backup_file|ID]
```

You can use these options with restore to selectively restore content:
```bash
./bssg.sh restore backup_id --no-posts  # Don't restore posts
./bssg.sh restore backup_id --no-drafts  # Don't restore drafts
./bssg.sh restore backup_id --no-pages  # Don't restore pages
./bssg.sh restore backup_id --no-config  # Don't restore configuration
```

### Build Options

```
Usage: ./bssg.sh build [options]

Options:
  -c, --clean-output      Empty the output directory before building
  -f, --force-rebuild     Ignore cache and rebuild all files
  --config FILE           Use a specific configuration file (e.g., my_config.sh)
                          instead of the default config.sh
  --src DIR               Override the SRC_DIR specified in the config file
  --pages DIR             Override the PAGES_DIR specified in the config file
  --drafts DIR            Override the DRAFTS_DIR specified in the config file
  --output DIR            Build the site to a specific output directory
  --templates DIR         Override the TEMPLATES_DIR specified in the config file
  --themes-dir DIR        Override the THEMES_DIR specified in the config file
  --theme NAME            Override the theme specified in the config file for this build
  --static DIR            Override the STATIC_DIR specified in the config file
  --site-url URL          Override the SITE_URL specified in the config file for this build
```

### Internationalization (i18n)

BSSG supports generating the site in different languages.

1.  **Configuration:**
    *   Set the desired language code in your `config.sh.local` file:
        ```bash
        SITE_LANG="es" # Use 'es' for Spanish, 'fr' for French, etc.
        ```
    *   If `SITE_LANG` is not set or the specified locale file doesn't exist, BSSG will default to English (`en`).

2.  **Locale Files:**
    *   Translations are stored in the `locales/` directory.
    *   Each language has its own file (e.g., `locales/en.sh`, `locales/es.sh`).
    *   These files contain exported shell variables for all translatable strings used in the templates and the build script (e.g., `export MSG_HOME="Home"`).

3.  **Adding a New Language:**
    *   Copy `locales/en.sh` to a new file named after the language code (e.g., `locales/fr.sh` for French).
    *   Translate the string values within the new file.
    *   Set `SITE_LANG` in `config.sh.local` to the new language code (e.g., `SITE_LANG="fr"`).
    *   Run `./bssg.sh build` to generate the site in the new language.

### Post and Page Management

*   **Edit Posts:**
    ```bash
    ./bssg.sh edit <post_filename.md>
    ```
*   **Delete Posts:**
    ```bash
    ./bssg.sh delete <post_filename.md>
    ```
*   **List Posts:**
    ```bash
    ./bssg.sh list
    ```
*   **List Tags:**
    ```bash
    ./bssg.sh tags
    ```

## Markdown Post Format

Posts should include YAML frontmatter at the beginning:

```markdown
---
title: Post Title
date: YYYY-MM-DD HH:MM:SS +TIMEZONE
lastmod: YYYY-MM-DD HH:MM:SS +TIMEZONE # Optional: Last modification date
tags: tag1, tag2, tag3
slug: custom-slug
image: /path/to/image.jpg
image_caption: Optional caption for the image
description: A brief summary of your post that will appear in listings, social media shares, and RSS feeds.
---

Content goes here...
```

- The `date` format supports full timestamps with timezone information. If you don't specify a time, the system will use the current time. If you don't specify a timezone, the system will use your local timezone.
- The optional `lastmod` field allows you to specify the date and time the content was last modified. It uses the same format as `date`. If omitted, it defaults to the `date` value. This field is used:
    - For the `<lastmod>` tag in `sitemap.xml`.
    - For the `<atom:updated>` tag in `rss.xml`.
    - To optionally display an "Updated on" date on the post page if it differs from the publish `date`.

### Post Description

The `description` field in the frontmatter lets you provide a brief summary of your post. This description will be used in:

- Post previews on the index, tag, and archive pages
- OpenGraph meta tags for better social media sharing
- RSS feed entries

If you don't specify a description, the system will automatically extract one from the beginning of your post content.

### Featured Images

The `image` field in the frontmatter allows you to specify an image path that will be displayed with your post. This can be:
- A relative path (e.g., `/images/photo.jpg`) that refers to a file in your static directory
- An absolute URL (e.g., `https://example.com/images/photo.jpg`)

The optional `image_caption` field lets you add a descriptive caption to the featured image.

When you specify an image, it will appear:
- At the top of individual post pages
- As a thumbnail in index pages, tag pages, and archive pages
- In the RSS feed
- In OpenGraph and Twitter metadata for better social media sharing

## Customization

To customize the appearance of your site, you can edit:

- `templates/header.html` - Site header and navigation
- `templates/footer.html` - Site footer
- CSS styles are generated in `output/css/style.css` 
- `config.sh.local` - Configuration file for site-wide settings

-   **`CUSTOM_CSS`:** (Optional) Specify a path (relative to the output directory root) to a custom CSS file. If set, a `<link>` tag will be added to the `<head>` of every generated page, after the theme's default `style.css`. The CSS file itself should be placed in your `$STATIC_DIR` (default: `static/`) to be copied to the output directory. Example: `CUSTOM_CSS="/css/my-styles.css"` (assuming `static/css/my-styles.css` exists).



### Configuration

The `config.sh` file contains the default configuration settings for the site generator:

```bash
# Directory configuration
SRC_DIR="src"            # Source directory for posts
PAGES_DIR="pages"        # Source directory for pages
DRAFTS_DIR="drafts"      # Source directory for drafts (posts and pages)
OUTPUT_DIR="output"        # Where the generated site is placed
TEMPLATES_DIR="templates"
THEMES_DIR="themes"
STATIC_DIR="static"
THEME="default"

# Build configuration
CLEAN_OUTPUT=false

# Site information
SITE_TITLE="My Journal"
SITE_DESCRIPTION="A personal journal and introspective newspaper"
SITE_URL="http://localhost"
AUTHOR_NAME="Anonymous" 
AUTHOR_EMAIL="anonymous@example.com"

# Content configuration
DATE_FORMAT="%Y-%m-%d %H:%M:%S %z"
TIMEZONE="local"  # Options: "local", "GMT", or a specific timezone
                  # Affects how dates are displayed in the generated site based on system interpretation.
SHOW_TIMEZONE="false" # Options: "true", "false". Determines if the timezone offset (e.g., +0200) is shown in displayed dates.
POSTS_PER_PAGE=10
ENABLE_ARCHIVES=true  # Enable or disable archives by year/month
URL_SLUG_FORMAT="Year/Month/Day/slug"  # Format for post URLs
RSS_ITEM_LIMIT=15 # Number of items to include in the RSS feed.
RSS_INCLUDE_FULL_CONTENT="false" # Options: "true", "false". If set to "true", the full post content will be included in the RSS feed description instead of the excerpt. Useful for readers that consume entire posts via RSS.
ENABLE_TAG_RSS=true # Options: "true", "false". If set to "true" (default), an additional RSS feed will be generated for each tag at `output/tags/<tag-slug>/rss.xml`.
```

#### Date Format Examples

- `DATE_FORMAT="%Y-%m-%d %H:%M:%S"` - 2023-05-15 14:30:45 (default)
- `DATE_FORMAT="%d-%m-%Y %H:%M:%S"` - 15-05-2023 14:30:45 (European format)
- `DATE_FORMAT="%b %d, %Y at %I:%M %p"` - May 15, 2023 at 02:30 PM (American format)
- `DATE_FORMAT="%d/%m/%Y"` - 15/05/2023 (date only)

#### Local Configuration

**IMPORTANT:** Do not modify `config.sh` directly. This file is part of the git repository and your changes could be lost during updates.

For local modifications, use the `config.sh.local` file instead. This file will override any settings in the main configuration and is ignored by git. You can override any variable from `config.sh`, including `SRC_DIR`, `PAGES_DIR`, and `DRAFTS_DIR`.

Example `config.sh.local`:
```bash
# Override site information for local development
SITE_TITLE="Development Site"
SITE_URL="http://localhost:8080"
AUTHOR_NAME="Your Name"
```

## Static Files

Any files placed in the `static/` directory will be automatically copied to the output directory during the build process. This is useful for including:

- Images
- Additional CSS files
- JavaScript files
- Downloadable files 
- Favicons
- Any other static assets

Example usage:
1. Place an image in `static/images/photo.jpg`
2. Reference it in your post as:
   ```markdown
   ![My Photo](/images/photo.jpg)
   ```
3. Or set it as a featured image in your post frontmatter:
   ```
   ---
   title: Post with Image
   image: /images/photo.jpg
   ---
   ```

## Themes

BSSG includes a variety of themes to customize the look of your site. Themes are organized in the `themes/` directory.  

### Some of the Available Themes

#### Modern Themes
- `default` - A clean and accessible blog theme
- `minimal` - A clean and minimal theme
- `dark` - Dark mode theme
- `flat` - Microsoft Metro/Modern UI inspired flat design
- `glassmorphism` - Modern frosted glass effect with blue/teal gradient
- `material` - Material Design inspired theme
- `art-deco` - Inspired by 1920s-30s Art Deco style with geometric patterns, elegant fonts, and gold/black/silver/jewel color palettes
- `bauhaus` - Inspired by the Bauhaus school, focusing on functionality, primary geometric shapes, primary colors plus black and white, and clean sans-serif typography
- `mid-century` - Mid-century modern aesthetic (1950s-60s), with clean lines, organic shapes, specific color palettes and characteristic fonts
- `swiss-design` - International Typographic Style, focused on grids, sans-serif typography (like Helvetica), strong visual hierarchy, and minimalism
- `nordic-clean` - Inspired by Scandinavian design, very minimal, airy, with plenty of white space, light and natural colors, and clean typography
- `braun` - Inspired by iconic Braun design with a focus on minimalism, functionality, and understated elegance
- `mondrian` - Inspired by Piet Mondrian's De Stijl artwork featuring primary colors, black grid lines, geometric shapes, and white backgrounds

#### Retro Computing Themes
- `amiga500` - Amiga 500 inspired theme
- `apple2` - Apple II inspired theme
- `atarist` - Atari ST inspired theme
- `c64` - Commodore 64 inspired theme
- `msdos` - MS-DOS inspired theme
- `terminal` - Terminal/console theme
- `zxspectrum` - ZX Spectrum inspired theme
- `nes` - Retro theme inspired by Nintendo Entertainment System, using the NES color palette and pixel art aesthetics
- `gameboy` - Retro theme inspired by Game Boy, using a light green background with dark green text for readability while maintaining nostalgic feel
- `tty` - Ultra-minimal theme simulating an old teletype output with monospace text on simple background and terminal-like aesthetics
- `mario` - Super Mario Bros inspired theme with iconic blue sky background, green pipes for navigation, brick blocks, question blocks, and the classic Mario color palette

#### Operating System Themes
- `beos` - BeOS inspired theme
- `macclassic` - Classic Mac OS inspired theme
- `macos9` - Mac OS 9 inspired theme
- `nextstep` - NeXTSTEP inspired theme
- `osx` - macOS inspired theme
- `win311` - Windows 3.11 inspired theme
- `win95` - Windows 95 inspired theme
- `win7` - Windows 7 inspired theme
- `winxp` - Windows XP inspired theme

#### Web Era Themes
- `web1` - Web 1.0 theme with HTML 3.2 aesthetics
- `web2` - Web 2.0 theme with glossy buttons and gradients
- `vaporwave` - Retro futurism with 80s aesthetics and neon colors
- `y2k` - Turn of the millennium aesthetic with bold colors and bubble effects
- `bbs` - Bulletin Board System theme with ANSI colors and ASCII art aesthetics

#### Content-Focused Themes
- `docs` - A clean, structured theme ideal for technical documentation with excellent code formatting and clear navigation
- `longform` - Optimized for reading long articles with highly readable typography, contained text width, and minimal distractions
- `reader-mode` - Simulates browser reader mode with almost total emphasis on text, sepia background, very readable serif font, and minimal graphic elements
- `text-only` - A step beyond minimalism using browser defaults with clean base typography for readability and lightning-fast loading

#### Special Themes
- `brutalist` - Raw, minimalist concrete-inspired design
- `newspaper` - Classic newspaper layout
- `diary` - Personal diary/journal style
- `random` - Selects a random theme (from the available themes) for each build

To use a theme, specify it in your config file:

```bash
THEME="msdos"
```

For a surprise each time, use the random option:

```bash
THEME="random"
```

### Theme Previews

BSSG includes a script to generate previews of all available themes. This is useful for seeing how each theme looks with your content before deciding which one to use.

To generate theme previews:

```bash
./generate_theme_previews.sh
```

This will create a directory called `example/` containing subdirectories for each theme, along with an index.html file that allows you to navigate between them.

You can also specify a custom SITE_URL for the previews:

```bash
./generate_theme_previews.sh --site-url "https://example.com/blog"
```

The script will use the SITE_URL from the following sources in order of precedence:
1. Command line argument (--site-url)
2. Local config file (config.sh.local)
3. Main config file (config.sh)
4. Default value (http://localhost)

Each theme preview will be accessible at `SITE_URL/theme` (e.g., `https://example.com/blog/dark`).

## Admin Interface

BSSG includes an admin interface for managing your blog. To use the admin interface:

1. Make sure you have Node.js installed
2. Navigate to the `admin` directory
3. Install dependencies:
   ```bash
   npm install
   ```
4. Start the admin server:
   ```bash
   npm start
   ```

The admin interface provides a user-friendly way to:
- Create and edit posts with a WYSIWYG Markdown editor
- Create and manage drafts
- Schedule posts for future publication
- Organize posts with tags
- View statistics about your blog

For more detailed information about the admin interface, see the [admin/README.md](admin/README.md) file.

### Post Scheduling

The admin interface allows you to schedule posts for future publication. When you create or edit a post, you can:

1. Choose "Schedule for later" option
2. Select the date and time for publication
3. The post will be stored as a draft until the scheduled time
4. At the scheduled time, the post will be automatically published

## Performance Features

BSSG is designed to be efficient even with large sites, using several performance-enhancing techniques:

### Incremental Builds

BSSG intelligently rebuilds only what has changed. When you run the build command, it:

1. Checks if source files have been modified since the last build
2. Checks if templates have been modified
3. Checks if configuration has changed
4. Only rebuilds files affected by changes

### Metadata Caching

The system maintains a cache of extracted metadata from markdown files to reduce repeated parsing:

- Extracted frontmatter is stored in `.bssg_cache/meta/`
- File index information is stored in `.bssg_cache/file_index.txt`
- Tags index information is stored in `.bssg_cache/tags_index.txt`

### Parallel Processing

If GNU parallel is installed on your system, BSSG can process multiple files simultaneously:

- Automatically detects GNU parallel and enables it for builds with many files
- Uses 80% of available CPU cores for optimal performance
- Falls back to sequential processing if parallel is not available

To take advantage of parallel processing, install GNU parallel:

```bash
# Debian/Ubuntu
sudo apt-get install parallel

# macOS
brew install parallel

# FreeBSD
pkg install parallel
```

## Site Configuration

Key configuration options:

```bash
# Site information
SITE_TITLE="My Journal"
SITE_DESCRIPTION="A personal journal and introspective newspaper" 
SITE_URL="http://localhost"
AUTHOR_NAME="Anonymous"
AUTHOR_EMAIL="anonymous@example.com"

# Content configuration
DATE_FORMAT="%Y-%m-%d %H:%M:%S %z"
TIMEZONE="local"  # Options: "local", "GMT", or a specific timezone
SHOW_TIMEZONE="false" # Options: "true", "false". Determines if the timezone offset (e.g., +0200) is shown in displayed dates.
POSTS_PER_PAGE=10
ENABLE_ARCHIVES=true  # Enable or disable archives by year/month
URL_SLUG_FORMAT="Year/Month/Day/slug"  # Format for post URLs
RSS_ITEM_LIMIT=15 # Number of items to include in the RSS feed.
RSS_INCLUDE_FULL_CONTENT="false" # Options: "true", "false". If set to "true", the full post content will be included in the RSS feed description instead of the excerpt. Useful for readers that consume entire posts via RSS.
ENABLE_TAG_RSS=true # Options: "true", "false". If set to "true" (default), an additional RSS feed will be generated for each tag at `output/tags/<tag-slug>/rss.xml`.
```

The `URL_SLUG_FORMAT` setting determines how your post URLs are structured. By default, it uses `Year/Month/Day/slug` which creates URLs like `http://yoursite.com/2023/01/15/my-post-title/`. 

Other possible formats include:
- `slug` - For simple `/post-title/` URLs
- `Year/slug` - For `/2023/post-title/` URLs
- `Year/Month/slug` - For `/2023/01/post-title/` URLs

## Future Plans

While BSSG is designed to be simple, there are a few enhancements planned for the future:

- **Stale Content Banner:** Add an option to display a banner on posts that haven't been updated in a configurable amount of time (e.g., more than X days/months).
- **Performance Refactor:** Address identified performance bottlenecks and improve the overall efficiency of the build process.

## Troubleshooting

### Common Issues

#### Missing Dependencies
If you encounter errors about missing commands, make sure you've installed all required dependencies for your platform as mentioned in the [Requirements](#requirements) section.

#### Permissions Issues
If you get "Permission denied" errors when running scripts, make them executable:
```bash
chmod +x bssg.sh
chmod -R +x scripts/*.sh
```

#### Pandoc Not Found
If you get errors about pandoc not being found, either install pandoc or switch to commonmark or markdown.pl in your config.sh.local:
```bash
# Use commonmark (recommended)
MARKDOWN_PROCESSOR="commonmark"

# Or use markdown.pl
MARKDOWN_PROCESSOR="markdown.pl"
```

#### Build Errors
If the build process fails, check:
1. That your Markdown files have proper frontmatter
2. That there are no syntax errors in your templates
3. That all required directories exist

For more help, use the issue tracker on the project's GitHub page.

## Author and License

BSSG has been developed by Stefano Marinelli (stefano@dragas.it) - https://it-notes.dragas.net

Read the announcement post detailing the journey behind BSSG:
[Launching BSSG: My Journey from Dynamic CMS to Bash Static Site Generator](https://it-notes.dragas.net/2025/04/07/launching-bssg-my-journey-from-dynamic-cms-to-bash-static-site-generator/)

This project is licensed under the BSD 3-Clause License - see the LICENSE file for details. 

## Documentation

- **Getting Started**: See the installation and usage instructions above.
- **Configuration**: Customize your site using the options in `config.sh`.
- **Templates**: Learn how to create custom templates in the `templates` directory.
- **Themes**: Explore the available themes in the `themes` directory.
- **Backup & Restore**: Use `./bssg.sh backup` and `./bssg.sh restore` to manage content backups. 
- **Development Blog**: Stay up-to-date with the latest release notes, development progress, and announcements on the official BSSG Dev Blog: [https://blog.bssg.dragas.net](https://blog.bssg.dragas.net)