---
title: About
date: 2024-04-02 12:00:00 +0200
slug: about
---

BSSG (Bash Static Site Generator) is a simple static site generator written in Bash. It processes Markdown files and builds a minimal, accessible website suitable for personal journals, daily writing, or introspective personal newspapers.

## Key Features

- Generates HTML from Markdown using pandoc or markdown.pl
- Supports post metadata (title, date, tags)
- Full date and time support with timezone awareness
- Post descriptions/summaries for previews, OpenGraph, and RSS
- Archives by year and month for chronological browsing
- Generates sitemap.xml and RSS feed
- Clean design with no JavaScript requirement (except for admin interface)
- Multiple themes available
- Draft posts and post scheduling
- Reading time calculation for posts
- Pagination for blog posts
- Incremental builds with file caching for improved performance

## Why BSSG?

BSSG is designed to be simple, fast, and lightweight. It's perfect for:

- Personal journals and blogs
- Daily writing practice
- Minimalist websites
- Technical documentation
- When you want to focus on content, not configuration

## Getting Started

To use BSSG, place your Markdown files in the `src/` directory and run `./bssg.sh build`. For more information, check out the [documentation](https://bssg.dragas.net).

## Author

BSSG has been developed by Stefano Marinelli (stefano@dragas.it) - [https://it-notes.dragas.net](https://it-notes.dragas.net)
