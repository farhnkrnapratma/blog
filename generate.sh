#!/usr/bin/env bash
set -euo pipefail

HOME_URL="https://fkp.my.id"
CDN_URL="https://cdn.fkp.my.id/static"
CDN_FAVICON="${CDN_URL}/favicons"
CDN_BLOG="${CDN_URL}/blog"
BASE_URL="blog.fkp.my.id"
SITE_URL="https://${BASE_URL}"
SITE_AUTHOR="Farhan Kurnia Pratama"
SITE_EMAIL="contact@fkp.my.id"
SITE_TITLE="Technical Insights by ${SITE_AUTHOR}"
SITE_DESCRIPTION="Technical insights from a Software Engineer specializing in Linux/Unix and FOSS, exploring secure software design, system security, and digital privacy."
SITE_LANGUAGE="en-US"
SITE_COPYRIGHT="Copyright $(date +%Y) ${SITE_AUTHOR}"
HIGHLIGHTJS_CDN="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1"

SRC_DIR="./src/template"
OUTPUT_DIR="./src"
RSS_FILE="${OUTPUT_DIR}/rss.xml"
INDEX_FILE="${OUTPUT_DIR}/index.html"
ROBOTS_FILE="${OUTPUT_DIR}/robots.txt"
SITEMAP_FILE="${OUTPUT_DIR}/sitemap.xml"

MAX_RSS_ITEMS=20

print_help()
{
  cat << EOF
NAME
    generate.sh - Static site generator for Technical Insights blog

SYNOPSIS
    ./generate.sh [OPTION]

DESCRIPTION
    Processes markdown templates to generate a static blog with HTML pages,
    an index, and an RSS feed. Output posts are organized by release year.

OPTIONS
    -n, --new
          Interactively scaffold a new blog post. Prompts for title,
          description, tags, and slug with validation, then generates
          the markdown template and frontmatter.

    -h, --help
          Display this help and exit.
EOF
}

check_deps()
{
  local missing=()
  for cmd in pandoc sed awk date wc tr; do
    command -v "$cmd" &> /dev/null || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[ERROR] Missing required tools: ${missing[*]}" >&2
    [[ " ${missing[*]} " == *" pandoc "* ]] \
      && echo "[ERROR] Install pandoc: https://pandoc.org/installing.html" >&2
    exit 1
  fi
}

get_frontmatter()
{
  local key="$1"
  local file="$2"
  awk "
    /^---/{count++; next}
    count == 1 && /^${key}:/ {
      sub(/^${key}:[[:space:]]*/, \"\")
      gsub(/^\"|\"$/, \"\")
      gsub(/^'|'$/, \"\")
      print
      exit
    }
    count >= 2 { exit }
  " "$file"
}

get_body()
{
  local file="$1"
  awk '
    /^---/{ count++; next }
    count >= 2 { print }
  ' "$file"
}

md_to_html()
{
  local input="$1"
  echo "$input" | pandoc \
    --from markdown \
    --to html \
    --no-highlight
}

xml_escape()
{
  echo "$1" \
    | sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e 's/"/\&quot;/g' \
      -e "s/'/\&apos;/g"
}

to_rfc822()
{
  local d="$1"
  local t="$2"
  if date --version &> /dev/null; then
    date -d "$d $t" '+%a, %d %b %Y %H:%M:%S %z'
  else
    date -jf '%Y-%m-%d %H:%M:%S' "$d $t" '+%a, %d %b %Y %H:%M:%S %z'
  fi
}

to_iso8601()
{
  local d="$1"
  local t="$2"
  local raw_tz
  if date --version &> /dev/null; then
    raw_tz=$(date -d "$d $t" +%z)
  else
    raw_tz=$(date -jf '%Y-%m-%d %H:%M:%S' "$d $t" +%z)
  fi
  echo "${d}T${t}${raw_tz:0:3}:${raw_tz:3:2}"
}

format_custom_datetime()
{
  local d="$1"
  local t="$2"
  local base
  local tz
  if date --version &> /dev/null; then
    base=$(date -d "$d $t" '+%a, %d %b %Y %H:%M')
    tz=$(date -d "$d $t" +%z)
  else
    base=$(date -jf '%Y-%m-%d %H:%M:%S' "$d $t" '+%a, %d %b %Y %H:%M')
    tz=$(date -jf '%Y-%m-%d %H:%M:%S' "$d $t" +%z)
  fi
  local sign="${tz:0:1}"
  local hours="${tz:1:2}"
  hours=$((10#$hours))
  echo "${base} GMT${sign}${hours}"
}

format_display_date()
{
  local raw="$1"
  if date --version &> /dev/null; then
    date -d "$raw" '+%a, %d %b %Y'
  else
    date -jf '%Y-%m-%d' "$raw" '+%a, %d %b %Y'
  fi
}

html_post()
{
  local title="$1"
  local date_str="$2"
  local description="$3"
  local url="$4"
  local content="$5"
  local tags_html="$6"
  local read_time="$7"
  local custom_datetime="$8"
  local meta_tags="$9"
  local iso8601_date="${10}"

  cat << HTML
<!doctype html>
<html lang="en" translate="no">
<head>
  <meta charset="UTF-8" />
  <link rel="preconnect" href="https://cdn.fkp.my.id" crossorigin="anonymous">
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${title} - ${SITE_TITLE}</title>
  <meta name="description" content="${description}" />
  <link rel="canonical" href="${url}" />
  <meta property="og:title" content="${title} - ${SITE_TITLE}" />
  <meta property="og:description" content="${description}" />
  <meta property="og:type" content="article" />
  <meta property="og:url" content="${url}" />
  <meta property="og:site_name" content="${BASE_URL}" />
  <meta property="og:image" content="${CDN_BLOG}/images/hero.png" />
  <meta property="og:image:secure_url" content="${CDN_BLOG}/images/hero.png" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:width" content="1280" />
  <meta property="og:image:height" content="640" />
  <meta property="og:image:alt" content="${SITE_DESCRIPTION}" />
  <meta property="og:locale" content="en_US" />
  <meta property="og:locale:alternate" content="id_ID" />
  <meta property="profile:first_name" content="Farhan Kurnia" />
  <meta property="profile:last_name" content="Pratama" />
  <meta property="profile:username" content="farhnkrnapratma" />
  <meta property="profile:gender" content="male" />
  <meta property="article:published_time" content="${iso8601_date}" />
  <meta property="article:author" content="${SITE_AUTHOR}" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${title} - ${SITE_TITLE}" />
  <meta name="twitter:description" content="${description}" />
  <meta name="twitter:image" content="${CDN_BLOG}/images/hero.png" />
  <meta name="twitter:label1" content="Reading time" />
  <meta name="twitter:data1" content="${read_time} min read" />
  ${meta_tags}
  <link rel="icon" href="${CDN_FAVICON}/favicon.ico" />
  <link rel="apple-touch-icon" sizes="180x180" href="${CDN_FAVICON}/apple-touch-icon.png" />
  <link rel="icon" type="image/png" sizes="32x32" href="${CDN_FAVICON}/favicon-32x32.png" />
  <link rel="icon" type="image/png" sizes="16x16" href="${CDN_FAVICON}/favicon-16x16.png" />
  <link rel="alternate" type="application/rss+xml" title="${SITE_TITLE}" href="${SITE_URL}/rss.xml" />
  <link rel="stylesheet" href="${HIGHLIGHTJS_CDN}/styles/github.min.css" media="(prefers-color-scheme: light)">
  <link rel="stylesheet" href="${HIGHLIGHTJS_CDN}/styles/github-dark-dimmed.min.css" media="(prefers-color-scheme: dark)">
  <script src="${HIGHLIGHTJS_CDN}/highlight.min.js"></script>
  <script>hljs.highlightAll();</script>
  <link rel="preconnect" href="https://api.fontshare.com" />
  <link rel="preconnect" href="https://cdn.fontshare.com" crossorigin="anonymous" />
  <link rel="preload" href="https://api.fontshare.com/v2/css?f[]=sentient@1,2&amp;f[]=satoshi@1,2&amp;f[]=jet-brains-mono@1,2&amp;display=swap" as="style" />
  <link rel="stylesheet" href="https://api.fontshare.com/v2/css?f[]=sentient@1,2&amp;f[]=satoshi@1,2&amp;f[]=jet-brains-mono@1,2&amp;display=swap" />
  <link rel="stylesheet" href="../style.css" />
</head>
<body>
  <div id="scroll-progress" class="fixed top-0 left-0 h-1 bg-fg-link z-50 transition-all duration-150" style="width: 0%"></div>
  <nav>
    <div>
      <a href="${HOME_URL}" class="link-hover">Home</a>
      <a href="${SITE_URL}/" class="link-active">Blog</a>
      <a href="${HOME_URL}/#contact" class="link-hover">Contact</a>
      <a href="${HOME_URL}/#support" class="link-hover">Support</a>
    </div>
  </nav>
  <main>
    <article>
      <header>
        <div class="flex flex-wrap gap-2 mb-3">${tags_html}</div>
        <h1>${title}</h1>
        <div class="author-section mt-0">
          <img src="${CDN_FAVICON}/apple-touch-icon.png" alt="${SITE_AUTHOR}" class="author-avatar" width="32" height="32" loading="lazy" />
          <div class="author-info">
            <span class="font-medium text-base text-fg-default dark:text-fg-white">${SITE_AUTHOR}</span>
            <div class="text-sm text-fg-muted font-satoshi">
              <time datetime="${date_str}">${custom_datetime}</time>
              <span class="middot">&middot;</span>
              <span>${read_time} min read</span>
            </div>
          </div>
        </div>
        <hr class="border-0 border-t border-border-disabled my-6" />
      </header>
      <section>
        ${content}
      </section>
    </article>
  </main>
  <footer>
    <div>
      Made with ♥️ &
      <a class="link-hover" href="https://tailwindcss.com">Tailwind</a>
    </div>
  </footer>
  <script src="../script.ts"></script>
</body>
</html>
HTML
}

html_index()
{
  local items="$1"

  cat << HTML
<!doctype html>
<html lang="en" translate="no">
<head>
  <meta charset="UTF-8" />
  <link rel="preconnect" href="https://cdn.fkp.my.id" crossorigin="anonymous">
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${SITE_TITLE}</title>
  <meta name="description" content="${SITE_DESCRIPTION}" />
  <link rel="canonical" href="${SITE_URL}/" />
  <meta property="og:title" content="${SITE_TITLE}" />
  <meta property="og:description" content="${SITE_DESCRIPTION}" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${SITE_URL}/" />
  <meta property="og:site_name" content="${BASE_URL}" />
  <meta property="og:image" content="${CDN_BLOG}/images/hero.png" />
  <meta property="og:image:secure_url" content="${CDN_BLOG}/images/hero.png" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:width" content="1280" />
  <meta property="og:image:height" content="640" />
  <meta property="og:image:alt" content="${SITE_DESCRIPTION}" />
  <meta property="og:locale" content="en_US" />
  <meta property="og:locale:alternate" content="id_ID" />
  <meta property="profile:first_name" content="Farhan Kurnia" />
  <meta property="profile:last_name" content="Pratama" />
  <meta property="profile:username" content="farhnkrnapratma" />
  <meta property="profile:gender" content="male" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${SITE_TITLE}" />
  <meta name="twitter:description" content="${SITE_DESCRIPTION}" />
  <meta name="twitter:image" content="${CDN_BLOG}/images/hero.png" />
  <link rel="icon" href="${CDN_FAVICON}/favicon.ico" />
  <link rel="apple-touch-icon" sizes="180x180" href="${CDN_FAVICON}/apple-touch-icon.png" />
  <link rel="icon" type="image/png" sizes="32x32" href="${CDN_FAVICON}/favicon-32x32.png" />
  <link rel="icon" type="image/png" sizes="16x16" href="${CDN_FAVICON}/favicon-16x16.png" />
  <link rel="manifest" href="https://cdn.fkp.my.id/static/blog/site.webmanifest">
  <link rel="alternate" type="application/rss+xml" title="${SITE_TITLE}" href="${SITE_URL}/rss.xml" />
  <link rel="preconnect" href="https://api.fontshare.com" />
  <link rel="preconnect" href="https://cdn.fontshare.com" crossorigin="anonymous" />
  <link rel="preload" href="https://api.fontshare.com/v2/css?f[]=sentient@1,2&amp;f[]=satoshi@1,2&amp;f[]=jet-brains-mono@1,2&amp;display=swap" as="style" />
  <link rel="stylesheet" href="https://api.fontshare.com/v2/css?f[]=sentient@1,2&amp;f[]=satoshi@1,2&amp;f[]=jet-brains-mono@1,2&amp;display=swap" />
  <link rel="stylesheet" href="./style.css" />
</head>
<body>
  <nav>
    <div>
      <a href="${HOME_URL}" class="link-hover">Home</a>
      <a href="${SITE_URL}/" class="link-active">Blog</a>
      <a href="${HOME_URL}/#contact" class="link-hover">Contact</a>
      <a href="${HOME_URL}/#support" class="link-hover">Support</a>
    </div>
  </nav>
  <main>
    <h1>Latest Blog</h1>
    <div class="grid-container">
      ${items}
    </div>
  </main>
  <footer>
    <div>
      Made with ♥️ &
      <a class="link-hover" href="https://tailwindcss.com">Tailwind</a>
    </div>
  </footer>
  <script src="./script.ts"></script>
</body>
</html>
HTML
}

rss_open()
{
  local build_date
  build_date=$(date '+%a, %d %b %Y %H:%M:%S %z')

  cat << XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:atom="http://www.w3.org/2005/Atom"
  xmlns:content="http://purl.org/rss/1.0/modules/content/"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$(xml_escape "$SITE_TITLE")</title>
    <link>${SITE_URL}/</link>
    <description>$(xml_escape "$SITE_DESCRIPTION")</description>
    <language>${SITE_LANGUAGE}</language>
    <copyright>$(xml_escape "$SITE_COPYRIGHT")</copyright>
    <lastBuildDate>${build_date}</lastBuildDate>
    <managingEditor>$(xml_escape "${SITE_EMAIL} (${SITE_AUTHOR})")</managingEditor>
    <webMaster>$(xml_escape "${SITE_EMAIL} (${SITE_AUTHOR})")</webMaster>
    <generator>Bash Script</generator>
    <docs>https://www.rssboard.org/rss-specification</docs>
    <ttl>60</ttl>
    <image>
      <url>${CDN_FAVICON}/android-chrome-192x192.png</url>
      <title>$(xml_escape "$SITE_TITLE")</title>
      <link>${SITE_URL}/</link>
    </image>
    <atom:link href="${SITE_URL}/rss.xml" rel="self" type="application/rss+xml" />
XML
}

rss_item()
{
  local title="$1"
  local url="$2"
  local description="$3"
  local pub_date="$4"
  local content="$5"
  local author="$6"

  cat << XML
    <item>
      <title>$(xml_escape "$title")</title>
      <link>${url}</link>
      <guid isPermaLink="true">${url}</guid>
      <description>$(xml_escape "$description")</description>
      <content:encoded><![CDATA[${content}]]></content:encoded>
      <pubDate>${pub_date}</pubDate>
      <dc:creator>$(xml_escape "$author")</dc:creator>
    </item>
XML
}

rss_close()
{
  cat << XML
  </channel>
</rss>
XML
}

robots_txt()
{
  cat << TXT
User-agent: *
Allow: /

Sitemap: ${SITE_URL}/sitemap.xml
TXT
}

sitemap_open()
{
  local home_lastmod="$1"

  cat << XML
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${SITE_URL}/</loc>
    <lastmod>${home_lastmod}</lastmod>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
XML
}

sitemap_item()
{
  local loc="$1"
  local lastmod="$2"
  local changefreq="${3:-monthly}"
  local priority="${4:-0.9}"

  cat << XML
  <url>
    <loc>${loc}</loc>
    <lastmod>${lastmod}</lastmod>
    <changefreq>${changefreq}</changefreq>
    <priority>${priority}</priority>
  </url>
XML
}

sitemap_close()
{
  cat << XML
</urlset>
XML
}

main()
{
  if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    print_help
    exit 0
  elif [[ ${1:-} == "-n" || ${1:-} == "--new" ]]; then

    while true; do
      read -r -p "Title: " title_input
      title_input=$(echo "$title_input" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
      if echo "$title_input" | grep -Eq "^[-A-Za-z0-9[:space:]:'\"/&%!?()*|,.]{1,60}$"; then
        break
      fi
      echo "[ERROR] Invalid title. Length 1-60 chars, accepted format only."
    done

    while true; do
      read -r -p "Description: " desc_input
      desc_input=$(echo "$desc_input" | awk '{sub(/./,toupper(substr($0,1,1)))}1')
      if echo "$desc_input" | grep -Eq "^[-A-Za-z0-9[:space:]:'\"/&%!?()*|,.]{1,160}$"; then
        break
      fi
      echo "[ERROR] Invalid description. Length 1-160 chars, accepted format only."
    done

    while true; do
      read -r -p "Tags (1-3 tags, comma separated): " tags_input

      tags_input=$(echo "$tags_input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z, ]//g')
      tags_input=$(echo "$tags_input" | sed 's/ *, */,/g' | sed 's/,,*/,/g' | sed 's/^,//;s/,$//')
      tags_input="${tags_input//,/, }"

      tag_count=$(echo "$tags_input" | awk -F, '{print NF}')

      if echo "$tags_input" | grep -Eq "^[a-z ]{1,20}(, [a-z ]{1,20}){0,2}$" && [[ $tag_count -ge 1 && $tag_count -le 3 ]]; then
        break
      fi
      echo "[ERROR] Invalid tags. Must be 1-3 tags, only letters and single spaces allowed per tag."
    done

    while true; do
      read -r -p "Slug: " slug_input
      if echo "$slug_input" | grep -Eq "^[a-z0-9-]+$"; then
        break
      fi
      echo "[ERROR] Invalid slug. Only lowercase letters, numbers, and hyphens allowed."
    done

    local date_val
    date_val=$(date +%Y-%m-%d)
    local time_val
    time_val=$(date +%H:%M:%S)

    mkdir -p "${SRC_DIR}/${slug_input}"
    cat << EOF > "${SRC_DIR}/${slug_input}/index.md"
---
title: ${title_input}
description: ${desc_input}
tags: ${tags_input}
date: ${date_val}
time: ${time_val}
slug: ${slug_input}
---

> ## TL;DR
>
> - First
> - Second
> - Third
> - ...

EOF
    echo "[INFO] Created scaffold: ${SRC_DIR}/${slug_input}/index.md"
    exit 0
  fi

  check_deps

  if [[ ! -d $SRC_DIR ]]; then
    echo "[ERROR] Posts directory not found: ${SRC_DIR}" >&2
    echo "[INFO] Creating ${SRC_DIR} for you..."
    mkdir -p "$SRC_DIR"
    exit 1
  fi

  echo "[INFO] Starting build -- source: ${SRC_DIR}, output: ${OUTPUT_DIR}"

  local rss_items=""
  local index_items=""
  local sitemap_items=""
  local latest_post_date=""
  local rss_count=0

  local post_files=()
  while IFS= read -r -d '' file; do
    post_files+=("$file")
  done < <(find "$SRC_DIR" -type f -name "index.md" -print0)

  if [[ ${#post_files[@]} -eq 0 ]]; then
    echo "[WARN] No markdown files found in ${SRC_DIR}"
    exit 0
  fi

  echo "[INFO] Found ${#post_files[@]} post(s), sorting by date..."

  declare -A post_dates
  declare -A post_times
  for file in "${post_files[@]}"; do
    local date time
    date=$(get_frontmatter "date" "$file")
    time=$(get_frontmatter "time" "$file")
    post_dates["$file"]="${date:-0000-00-00}"
    post_times["$file"]="${time:-00:00:00}"
  done

  IFS=$'\n' read -r -d '' -a sorted_files < <(
    for f in "${!post_dates[@]}"; do
      echo "${post_dates[$f]} ${post_times[$f]}|${f}"
    done | sort -r -t'|' -k1 | awk -F'|' '{print $2}' && printf '\0'
  ) || true

  for file in "${sorted_files[@]}"; do
    local title date time description slug tags tags_html meta_tags

    title=$(get_frontmatter "title" "$file")
    date=$(get_frontmatter "date" "$file")
    time=$(get_frontmatter "time" "$file")
    description=$(get_frontmatter "description" "$file")
    slug=$(get_frontmatter "slug" "$file")
    tags=$(get_frontmatter "tags" "$file")

    title="${title:-$(basename "$(dirname "$file")")}"
    date="${date:-$(date +%Y-%m-%d)}"
    time="${time:-00:00:00}"
    description="${description:-}"
    slug="${slug:-$(basename "$(dirname "$file")")}"

    if [[ -z $latest_post_date ]]; then
      latest_post_date="$date"
    fi

    tags_html=""
    meta_tags=""
    if [[ -n $tags ]]; then
      IFS=',' read -ra TAG_ARRAY <<< "$tags"
      for tag in "${TAG_ARRAY[@]}"; do
        tag=$(echo "$tag" | awk '{$1=$1};1')
        if [[ -n $tag ]]; then
          safe_tag=$(xml_escape "$tag")
          tags_html+="<span class=\"tag\">${safe_tag}</span>"
          if [[ -z $meta_tags ]]; then
            meta_tags+="<meta property=\"article:tag\" content=\"${safe_tag}\" />"
          else
            meta_tags+=$'\n  '"<meta property=\"article:tag\" content=\"${safe_tag}\" />"
          fi
        fi
      done
    fi

    local post_url="${SITE_URL}/${slug}/"
    local post_dir="${OUTPUT_DIR}/${slug}"
    local body html_content word_count read_time

    local rfc_date display_date iso8601_date
    rfc_date=$(to_rfc822 "$date" "$time")
    display_date=$(format_display_date "$date")
    iso8601_date=$(to_iso8601 "$date" "$time")

    echo "[BUILD] Processing post: slug=${slug} date=${date} time=${time}"

    body=$(get_body "$file")
    html_content=$(md_to_html "$body")

    word_count=$(echo "$body" | wc -w | awk '{print $1}')
    read_time=$((word_count / 130))
    if ((read_time < 1)); then
      read_time=1
    fi

    mkdir -p "$post_dir"
    find "$(dirname "$file")" -maxdepth 1 -type f -not -name "*.md" -exec cp {} "$post_dir/" \;

    html_post \
      "$title" \
      "$date" \
      "$description" \
      "$post_url" \
      "$html_content" \
      "$tags_html" \
      "$read_time" \
      "$display_date" \
      "$meta_tags" \
      "$iso8601_date" \
      > "${post_dir}/index.html"

    index_items+="<a href=\"./${slug}/\" class=\"card\">
      <div class=\"card-header flex flex-col gap-3\">
        <div class=\"flex flex-wrap gap-2\">${tags_html}</div>
        <h2>${title}</h2>
        <p>${description}</p>
      </div>
      <hr />
      <div class=\"card-footer\">
        <div class=\"author-section\">
          <img src=\"${CDN_FAVICON}/apple-touch-icon.png\" alt=\"${SITE_AUTHOR}\" class=\"author-avatar\" width=\"32\" height=\"32\" loading=\"lazy\" />
          <div class=\"author-info\">
            <span class=\"font-medium\">${SITE_AUTHOR}</span>
            <div>${display_date} <span class=\"middot\">&middot;</span> ${read_time} min read</div>
          </div>
        </div>
      </div>
    </a>\n"

    if ((rss_count < MAX_RSS_ITEMS)); then
      rss_items+=$(
        rss_item \
          "$title" \
          "$post_url" \
          "$description" \
          "$rfc_date" \
          "$html_content" \
          "$SITE_AUTHOR"
      )
      rss_count=$((rss_count + 1))
    fi

    sitemap_items+=$(
      sitemap_item \
        "$post_url" \
        "$date"
    )
    sitemap_items+=$'\n'
  done

  echo "[INFO] Generating RSS feed -> ${RSS_FILE}"
  {
    rss_open
    echo "$rss_items"
    rss_close
  } > "$RSS_FILE"

  echo "[INFO] Generating blog index -> ${INDEX_FILE}"
  html_index "$(echo -e "$index_items")" > "$INDEX_FILE"

  if [[ -z $latest_post_date ]]; then
    latest_post_date=$(date +%Y-%m-%d)
  fi

  echo "[INFO] Generating robots -> ${ROBOTS_FILE}"
  robots_txt > "$ROBOTS_FILE"

  echo "[INFO] Generating sitemap -> ${SITEMAP_FILE}"
  {
    sitemap_open "$latest_post_date"
    echo "$sitemap_items"
    sitemap_close
  } > "$SITEMAP_FILE"

  echo ""
  echo "[DONE] ${#sorted_files[@]} post(s) built successfully"
  echo "[DONE] HTML   -> ${OUTPUT_DIR}/[slug]/"
  echo "[DONE] RSS    -> ${RSS_FILE}"
  echo "[DONE] Index  -> ${INDEX_FILE}"
  echo "[DONE] Robots -> ${ROBOTS_FILE}"
  echo "[DONE] Sitemap -> ${SITEMAP_FILE}"
}

main "$@"
