# Authoring guide

This template lets several authors contribute content without touching the site
layout or the shared files. Everything an author writes lives in their own
folder, and the plugins mirror it into the site at build time.

## Who writes what

| Who | Where |
| --- | --- |
| Authors | `authors-src/<author>/` |
| Site owner | top level category pages (`author.md`, `guides.md`, ...), `index.md`, `about.md`, `_config.yml`, `docs/` |
| Either | sub category pages such as `guides/advanced.md`; the owner commits them, or an author provides one with `category_page: true` |

## Author folder anatomy

```
authors-src/alice/
├── author.md                  # profile page, categories: [author]
├── _includes/note.html        # partials for {% include_author %}
├── _posts/
│   ├── 2025-01-15-hello.md    # dated post filename
│   └── using-this-template.md # undated: the plugin adds the date prefix
├── _drafts/work-in-progress.md
├── guides/getting-started.md  # page that joins the guides category
└── sandbox.md                 # uncategorized page
```

`authors-src` is the default; change it with `authors.source` in `_config.yml`.
Folder names become part of the site (`_includes/<author>/`), so prefer short
ASCII slugs.

## Mapping rules

| Source file under `authors-src/<author>/` | Published as |
| --- | --- |
| page with `categories: [guides]` and a `title` | `guides/<title slug>.md` → `/guides/<title slug>.html` |
| page with a nested category, `categories: [guides/advanced]` | `guides/advanced/<title slug>.md` |
| page with several usable categories | one copy per category, e.g. `guides/...` and `notes/...` |
| page with `category_page: true` | the category page itself, `guides/advanced.md`; no member copy |
| page whose categories are not usable | `authors/<author>/<relative path>` |
| `author.md` without categories | `authors/<author>/author.md` |
| `_posts/**` | `_posts/<author>/**` (a real Jekyll post) |
| `_drafts/**` | `_drafts/<author>/**` (built only with `--drafts`) |
| `_includes/**` | `_includes/<author>/**` |
| `_layouts/**`, `_sass/**`, `_data/**` | same directory, namespaced by author |
| `_plugins/**` | skipped (plugins load before the mirror) |

A category is usable only when its category page exists: `<category>.md`,
`guides/advanced.md` for `guides/advanced`. Copies for missing categories are
skipped with a warning.

Categories nest through a slash path. `categories: [guides, notes]` still means
two sibling copies; use `categories: [guides/advanced]` for a child category.
A page that declares several categories appears in every matching category list,
but it joins the chapter (`order`, previous/next) of one category only: the
deepest one it declares.

The published file name comes from the front matter `title`, slugified by
Jekyll (Unicode is preserved). Without a title the source file name is used.
Add `permalink:` to the front matter if you need a custom URL.

## Front matter reference

| Key | Used for |
| --- | --- |
| `layout` | `page`, `article` (chapter root / ordered pages), `post` (posts) |
| `title` | Page title, category list label and target file name |
| `categories` / `category` | Category membership; array or space separated string; a slash creates a sub category |
| `order` | Order inside a category chapter (`1`, `1.1`, `1.2`, `2`, ...) |
| `tags` | Tag chips and `/tags/<tag>.html` index pages |
| `date` | Publication date; used for posts without a dated filename |
| `modified_date` | "Updated on" date and recency sorting |
| `license` | Per-page license; inherited from the category root when using `layout: article` |
| `main_part` | Numeric section weight for the home page list |
| `category_list` | `false` disables the automatic list on a category page |
| `category_page` | `true` turns this author file into the category page of its category |

## Category pages

A category page is the file named after its category: `guides.md` for `guides`,
`guides/advanced.md` for `guides/advanced`:

```markdown
---
layout: page
title: Guides
main_part: 3
---

Step-by-step guides.
```

During the build the page gets a list of:

- its direct sub categories, as links to their category pages;
- every page directly in `guides/` (author content and pages committed in that
  directory), ordered by `order` when present and by path otherwise;
- every post whose `categories` include `guides`, newest first.

Deeper pages are not repeated here; they appear on the category page that owns
them. Each item shows the page title and links to it. Options:

- `category_list: false` — no automatic list;
- `{% category_list %}` — insert the list manually where you want it (the
  automatic append is then skipped);
- `{% category_list guides/advanced %}` — list another category's members.

### Category pages written by authors

An author can provide a sub category page from their own folder:

```markdown
---
layout: page
title: Tech notes
category_page: true
---
```

The category is taken from `categories` when present, otherwise from the folder
path below the author folder: `alice/guides/tech/index.md` hosts `guides/tech`.
Three rules apply:

- only sub categories (`guides/tech`); top level categories stay with the site
  owner;
- a category page that already exists on disk always wins, and the author file
  falls back to `authors/<author>/...`;
- the file is a mirror, so it is written for the build and removed afterwards —
  keep the source in `authors-src/`.

A category page is a navigation hub: it is not part of a chapter, so it never
gets previous/next links or a chapter root of its own.

### Posts index (`_posts.md`)

`_posts.md` in the site root is the category page of the listing-only category
`_posts`, so it collects every post that declares `categories: [_posts]`,
newest first:

```markdown
---
layout: page
title: Posts
main_part: 4
---
```

- The file is published at `/_posts.html`; `main_part` puts it in the home page
  "Sections" list.
- `_posts` can be listed but is never a valid mirror target, so nothing is ever
  written into the `_posts/` collection directory.
- Jekyll drops every entry whose name starts with `_`. The plugin adds
  `_posts.md` and `_posts.markdown` to `site.include` before the site is read, so
  the page works without editing `_config.yml`.
- Only `_posts` itself is supported; nested ids such as `_posts/tech` are not.

## Author profiles

Every author creates `author.md` with `categories: [author]`:

```markdown
---
layout: page
title: Alice
categories: [author]
date: 2025-01-01
---

A short profile.
```

The site owner must create `author.md` at the site root once; after that all
profiles appear at `/author/<title>.html` and on the Authors page.

## Ordered chapters

Give pages in a category an `order` value and add a root page with `order: 0`:

```markdown
---
layout: article
title: Overview
categories: [guides]
order: 0
license: "CC BY 4.0"
---
```

- ordered pages get previous/next links;
- every ordered page links back to the root page ("Back to category");
- the root page shows a nested table of contents with the numbers, followed by
  one entry per sub category;
- the category page lists its members in the same `order`;
- `layout: article` pages inherit the root page's license, and a sub category
  with no root of its own inherits from its parent category;
- the root of a sub category also links back to its parent category page
  ("Back to parent").

A page that declares several categories and an `order` joins one chapter only —
the deepest category it declares — and the build warns about it. That keeps the
single valued previous/next data unambiguous.

`_plugins/CategoryOrder.rb` implements the ordering and chapter navigation,
`_plugins/DefaultLicense.rb` the license inheritance.

## Up links

Every page that belongs to a category gets exactly one "back up" link, at the
top of the article or at the bottom of the page. The link text names its target:
`☰ Back to Guides`, `☰ Back to Overview`, `☰ Back to Home`.

| Page | Link | Points at |
| --- | --- | --- |
| ordered member (`order: 1`) | Back to *chapter root title* | the chapter root page |
| ordered sub page (`order: 1.1`) | Back to *root*, plus Back to *order parent* | root page and the order parent |
| member without `order` | Back to *category page title* | the category page |
| post | Back to *category page title* | its category page, e.g. `/_posts.html` |
| chapter root (`order: 0`) | Back to *category page title* | the category page |
| sub category page | Back to *parent category page title* | the parent category page |
| top level category page | Back to Home | `/` |

Pages that belong to no category (`about.md`, `index.md`, tag pages, the
uncategorised fallback pages, `404.html`) get no up link. When a page has both a
`root` and a `parent` pointing at the same URL, only one link is rendered.

## Per-author includes

Put reusable partials in `<author>/_includes/` and include them with:

```liquid
{% include_author note.html title="Tip" body="Rendered from this author's _includes folder." %}
```

The tag looks in `_includes/<author>/` first and falls back to the shared
`_includes/` folder. Author folder names must be ASCII slugs for this to work;
the build logs a warning otherwise.

## Posts, tags and drafts

- `_posts/**` is mirrored to `_posts/<author>/**` and behaves like a normal
  Jekyll post.
- With `categories: [_posts]` and the default permalink, posts are published at
  `/_posts/<title>.html` and collected on the `/_posts.html` index page (see
  below). Use `[_posts]` on its own: a second category would be prepended to the
  URL (`/blog/_posts/<title>.html`).
- Post filenames do not need a date: the plugin prefixes the front matter
  `date` (or `modified_date`, or the file modification time).
- `tags:` generates `/tags/<tag>.html` index pages and tag chips in the footer.
- Drafts in `_drafts/` are mirrored but only built with
  `bundle exec jekyll serve --drafts`.
- `modified_date` adds an "Updated on" line and influences the "Recently
  updated" sidebar.
- Posts keep Jekyll's built-in previous/next links (ordered by date); the
  category `order` only applies to pages.

## Images and assets

There is no automatic mirroring of assets into category folders. Put images next
to your content and reference them under the author path they are published at:

```markdown
![Screenshot](/authors/alice/guides/screenshot.png)
```

Any file that is not a page with front matter (images, PDFs, ...) is mirrored to
`authors/<author>/<relative path>`.

## Warnings and fixes

| Warning | Meaning |
| --- | --- |
| `Category page missing (create <category>.md, or set category_page: true on an author file)` | The category page does not exist; the copy was skipped and the page fell back to `authors/<author>/...`. |
| `Invalid category value, skipped` | A category segment contains a path separator, starts with `_` or `.`, is a reserved name (`tmp`, `authors`, `authors-src`) or uses a character Windows rejects. |
| `Top level category pages are created by the site owner` | `category_page: true` with a single level category; only sub categories are accepted from authors. |
| `Category page is maintained by the site owner` | A file already exists at that path; the author copy fell back to `authors/<author>/...`. |
| `Another author already provides this category page` | Two authors claimed the same sub category; the first author in sort order wins. |
| `category_page: true does not apply inside _posts/ or _drafts/` | The switch only works for regular content files. |
| `A category page should declare one category` | More than one category was declared; the deepest one is used. |
| `Copies skipped because the target is a category page` | A page title would collide with a category page; that copy falls back instead of overwriting it. |
| `Target exists and is not managed by this plugin` | A file already exists at the target path; delete it and rebuild to let the plugin map it. |
| `Target was modified externally` | The file was edited after the plugin wrote it; the plugin leaves it alone. |
| `Author folder ... is unsafe for include paths` | Rename the author folder to an ASCII slug. |
| `Skipped N author plugin file(s)` | `_plugins/` inside an author folder is not supported. |

## Removing the demo content

1. Delete `authors-src/alice/` and `authors-src/bob/` (or replace them).
2. Delete `guides/overview.md`.
3. Remove or rename `author.md`, `guides.md` and update `header_pages` in
   `_config.yml`. Keep `_posts.md` if you want a posts index.
4. Replace the text in `index.md` and `about.md`.
