---
title: BSSG Features and Examples
date: 2025-04-01 09:30:00 +0200
tags: bssg, tutorial, examples, static-site
slug: bssg-features-examples
description: A detailed overview of BSSG's key features with practical examples showing how to get the most out of this Bash Static Site Generator.
image: https://picsum.photos/537/354
image_caption: Sample, random pic from picsum
---

BSSG (Bash Static Site Generator) offers a powerful yet simple approach to creating static websites. This post demonstrates some of its key features with practical examples.

## Post Metadata

BSSG supports rich metadata for posts through YAML frontmatter:

```markdown
---
title: Your Post Title
date: 2025-04-01 09:30:00 +0200
tags: tag1, tag2, tag3
slug: custom-url-slug
image: /path/to/featured-image.jpg
image_caption: A caption for your featured image
description: A brief summary of your post for previews and SEO
---
```

## Markdown Support

BSSG fully supports standard Markdown syntax for content:

### Headings

```markdown
# H1 Heading
## H2 Heading
### H3 Heading
```

### Lists

```markdown
- Unordered list item 1
- Unordered list item 2
  - Nested item

1. Ordered list item 1
2. Ordered list item 2
```

### Code Blocks

```markdown
```javascript
function hello() {
  console.log("Hello, BSSG!");
}
```

### Blockquotes

```markdown
> This is a blockquote.
> It can span multiple lines.
```

## Theme System

BSSG includes multiple themes that completely change the look and feel of your site:

- `default` - Clean and minimal design
- `web1` - Web 1.0 nostalgic design
- `brutalist` - Raw, minimalist concrete-inspired design
- `vaporwave` - Retro futurism with 80s aesthetics
- `glassmorphism` - Modern frosted glass effect with gradient backgrounds

And many, many more! You can switch themes by editing your `config.sh.local` file:

```bash
THEME="macclassic"
```

## Command Examples

### Creating a new post:

```bash
./bssg.sh post
```

### Building the site:

```bash
./bssg.sh build
```

### Listing all posts:

```bash
./bssg.sh list
```

### Creating a backup:

```bash
./bssg.sh backup
```

## Output Example

When you build your BSSG site, it generates clean HTML with excellent accessibility features:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Post Title - Site Name</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Post description for SEO">
  <!-- OpenGraph tags for social media -->
  <meta property="og:title" content="Post Title">
  <meta property="og:description" content="Post description">
  <meta property="og:url" content="https://example.com/post-slug">
  <link rel="stylesheet" href="/css/style.css">
</head>
<body>
  <header>
    <!-- Navigation -->
  </header>
  <main>
    <article>
      <h1>Post Title</h1>
      <time datetime="2025-04-01T09:30:00+02:00">April 1, 2025</time>
      <!-- Post content -->
    </article>
  </main>
  <footer>
    <!-- Footer content -->
  </footer>
</body>
</html>
```

## Conclusion

BSSG provides a streamlined approach to website creation with minimal dependencies. It's perfect for writers who want to focus on content rather than complex configurations or JavaScript frameworks. 
