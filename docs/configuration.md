# Configuration reference

All configuration lives in `_config.yml`. The template only adds the `authors`
block and a `mathjax` switch on top of standard Jekyll options.

## Site settings

| Key | Default | Purpose |
| --- | --- | --- |
| `title` | `Jekyll Authors Template` | Site title in the header, feed and SEO tags |
| `description` | | Meta description used by `jekyll-seo-tag` |
| `lang` | `en` | `<html lang>` value |
| `author` | `Your Name` | Footer name and SEO author |
| `email` | `you@example.com` | Footer mail link (optional) |
| `social_links` | GitHub example | Footer links; `title` is a Font Awesome brand name |
| `license` | placeholder | Footer license line; a page's `license` front matter wins |
| `baseurl` | empty | Set for project pages (`/my-repo`) |
| `url` | empty | Canonical site URL (`https://example.com`) |
| `permalink` | `/:categories/:title:output_ext` | Post URLs; pages keep their path |
| `header_pages` | `about.md`, `guides.md`, `author.md` | Top navigation |
| `date_format` | `%B %-d, %Y` | Dates in headers and the sidebar |
| `mathjax` | `false` | Include MathJax on every page |
| `google_analytics` | unset | Enables the analytics include when set |
| `exclude` | `README.md`, `LICENSE.txt`, `docs` | Repository files that are not published |

## Author settings

```yaml
authors:
  source: authors-src   # one sub-folder per author
  page_dir: authors     # target for content without a usable category
  keep_mirror: false    # true = keep the mirrored files after the build
```

| Key | Purpose |
| --- | --- |
| `source` | Directory that contains the author folders, relative to the site root (an absolute path is also accepted). It is excluded from the output automatically. |
| `page_dir` | Directory used for author content that does not join a category (default `authors`). |
| `keep_mirror` | Keep the generated files after the build for debugging. Normally everything is cleaned up again. |

The generated mirror manifest is written to
`.jekyll-cache/authors-mirror.json` (git-ignored). It records a sha256 for every
file the plugin wrote, so external edits are never overwritten or deleted.

## Plugins

### Authors (`_plugins/Authors.rb`)

Mirrors `authors.source/<author>/` into the site before it is read, applies the
category rules and removes the mirrored files after the build. Front matter
`categories` decides the destination; `title` decides the file name. Also
provides the `{% include_author file.html %}` tag.

### CategoryList (`_plugins/CategoryList.rb`)

Adds a member list to category pages. A category page is the page whose path
without its extension is a category id: `guides.md` hosts `guides`,
`guides/advanced.md` hosts `guides/advanced`. Author provided category pages
(`category_page: true`) count as well, even though the mirror writes them.

The list contains the direct sub categories first, then the pages directly under
`<category>/` (ordered by `order` when set, by path otherwise) and the posts
whose categories match (newest first), linked by title. Deeper pages are not
repeated in the parent list. Disable it per page with `category_list: false`, or
place `{% category_list %}` / `{% category_list guides/advanced %}` manually.

`_posts` is a listing-only category: `_posts.md` in the site root hosts it, so
every post declaring `categories: [_posts]` is listed on `/_posts.html`. Being
listing-only, it can never be a mirror target — nothing is written into the
`_posts/` collection directory. Because Jekyll skips entries starting with `_`,
the plugin also adds `_posts.md` / `_posts.markdown` to `site.include` before the
site is read.

### CategoryOrder (`_plugins/CategoryOrder.rb`)

Orders pages inside one category: it builds the previous/next chain, the
"Back to category" root link, the "Back to parent" link for nested orders and a
nested table of contents. Pages join a chapter by declaring a category and an
`order`; `order: 0` marks the chapter root. Posts keep Jekyll's own date based
neighbours (the post layout also renders them through `page-nav.html`). The
rendered page navigation comes from `_includes/page-nav.html`; the table of
contents from `page.toc_html` in the page/article layouts.

A document joins exactly one chain — its primary category, the deepest one it
declares — so a page with several categories cannot receive conflicting
previous/next data. The root's table of contents ends with one entry per direct
sub category, and the root of a sub category links back to its parent category
page. Category pages are navigation hubs and never join a chain.

The generator also fills the "up" links used by `_includes/page-nav.html` and the
page/article/post layouts: every document gets `page.root` pointing at its
chapter root, or at its category page when the category has no chapter root
(posts included); every category page gets `page.parent` pointing at its parent
category page, or at the home page when it is top level. See "Up links" in
`docs/authoring.md` for the full table.

### DefaultLicense (`_plugins/DefaultLicense.rb`)

Lets `layout: article` pages inherit the `license` of their chapter root
(`order: 0` page of the same category). A sub category with no root of its own
inherits from its parent category.

### Recent (`_plugins/Recent.rb`)

Collects the five most recently updated posts and `article`/`post` pages
(`modified_date` or `date`) into `site.data.recent`, rendered by
`_includes/latest.html`.

### TagsPage (`_plugins/TagsPage.rb`)

Generates one page per tag at `/tags/<tag>.html`, listing every post and page
that uses the tag.

### MainPart (`_plugins/MainPart.rb`)

Collects pages with a numeric `main_part` front matter value into
`site.data.main_part_page`, ordered descending. `_layouts/home.html` uses it for
the "Sections" list, so the home page itself stays plain Markdown.

### PluginUtils (`_plugins/PluginUtils.rb`)

Shared helper that normalises `categories` and `tags` values, so both
`[a, b]` and the space separated `a b` form work everywhere. It is also the one
place that defines what a valid category id is: slash separated segments, folded
repeated separators, backslashes treated as separators, reserved names and
Windows-invalid characters rejected, plus the helpers for parent, ancestors,
depth and the primary category of a document.

`LISTING_CATEGORIES` (`_posts`) is the one exception: `category_listable?` accepts
those ids for grouping documents into a list, while the stricter
`category_valid?` still rejects them, which is what keeps them out of the mirror
targets and out of chapter chains.

## Build pipeline

For every build (`jekyll build`, and every rebuild in `jekyll serve`):

1. `:site, :after_reset` — `Authors.mirror` copies author content into place,
   excludes the author folder from the output and records the manifest;
   `CategoryList.allow_listing_pages` adds the `_`-prefixed listing pages to
   `site.include` so Jekyll reads them.
2. `read` — Jekyll reads the mirrored pages, posts, layouts and includes.
3. `:site, :post_read` — every category copy's `page.categories` is narrowed to
   its own category, so CategoryOrder and DefaultLicense see one copy per
   category.
4. `generate` — MainPart, TagsPage, Recent, CategoryOrder and DefaultLicense
   build their data.
5. `render` / `write` — pages, posts and static files are written to `_site`.
6. `at_exit` — mirrored files are deleted again (unless `keep_mirror: true`).

## Deployment

`.github/workflows/jekyll-gh-pages.yml` builds the site with
`bundle exec jekyll build` and deploys it with `actions/deploy-pages`.

Pages must be enabled once for the repository:

1. **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Re-run the workflow.

Without that setting `actions/configure-pages` fails with
`Get Pages site failed ... Not Found`, because the Pages API returns 404 until
the site is enabled. Private repositories also need a plan that supports Pages.

If the Pages run shows `actions/jekyll-build-pages@v1`, `github-pages v232`,
`jekyll v3.10.0` or `Unknown tag 'include_author'`, the Source is still
**Deploy from a branch**: that builder runs Jekyll in safe mode, ignores
`_plugins/` and publishes the author folders raw. Select **GitHub Actions**
instead.

The workflow runs `bundle exec jekyll build --baseurl "${{ steps.pages.outputs.base_path }}"`
so user pages (`<user>.github.io`, base path `""`) and project pages
(`<user>.github.io/<repo>`, base path `/<repo>`) both work without editing
`_config.yml`. Set `url` in `_config.yml` if you need absolute canonical URLs.

Custom plugins are the core of this template, and the classic GitHub Pages
builder runs Jekyll in safe mode, which **ignores `_plugins/`**. If you deploy
elsewhere (Netlify, Cloudflare Pages, your own CI), make sure the build command
is `bundle exec jekyll build` rather than a safe-mode GitHub Pages build.

## Changing the author folder

1. Rename the folder (e.g. `authors-src` → `content`).
2. Set `authors.source` in `_config.yml`.
3. Keep `page_dir` at `authors` unless you also want to rename the fallback tree.

If an old `tmp/` folder is still present while `authors.source` points
somewhere else, the build warns that `tmp/` would be published as normal site
content; move or delete it.
