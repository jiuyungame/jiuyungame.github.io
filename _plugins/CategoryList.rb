require "cgi"

module Jekyll
  # Automatic member lists for category pages.
  #
  # A category page is the page that hosts a category: the path without its
  # extension is the category id. So guides.md hosts "guides" and
  # guides/advanced.md hosts "guides/advanced". A category page provided by an
  # author (see _plugins/Authors.rb, `category_page: true`) counts too, even
  # though the mirror writes it.
  #
  # A listing-only category (see PluginUtils::LISTING_CATEGORIES) works the same
  # way without touching this module: _posts.md at the site root hosts "_posts",
  # so every post declaring `categories: [_posts]` is listed on /_posts.html.
  # Jekyll drops files starting with "_", which is why allow_listing_pages adds
  # those page names to site.include before the site is read.
  #
  # A category page lists:
  #   - its direct sub categories, linked to their category pages;
  #   - the pages that live directly in <category>/ and every post whose
  #     categories include <category>, newest first.
  # Sub category content is not repeated in the parent list; deeper pages show
  # up on the category page that owns them.
  #
  # Opt out for a single page with `category_list: false` in its front matter, or
  # place {% category_list %} / {% category_list guides/advanced %} manually to
  # control where the list appears (the automatic append is then skipped).
  module CategoryList
    class << self
      # :pages, :pre_render hook: append the list tag to category pages.
      def inject(page)
        return if page.nil?
        return if page.data["category_list"] == false
        return if page.content.to_s.include?("category_list")

        site = page.respond_to?(:site) ? page.site : nil
        return if site.nil?
        return unless category_page?(page, site)
        return if entries(page, site).empty?

        page.content = "#{page.content}\n\n{% category_list %}\n"
      end

      def render(page, site, explicit = nil)
        return "" if site.nil?

        category = category_for(page, site, explicit)
        return "" if category.nil?

        items = entries(page, site, category)
        return "" if items.empty?

        %(<ul class="category-list">#{items.join}</ul>)
      end

      # Jekyll skips every entry whose name starts with "_", so a listing page
      # such as _posts.md has to be added to site.include explicitly. Only the
      # page file names are included, never the bare directory, so the post
      # sources stay in the collection where they belong.
      def allow_listing_pages(site)
        return if site.nil?

        files = Jekyll::PluginUtils::LISTING_CATEGORIES.flat_map do |id|
          %W[#{id}.md #{id}.markdown]
        end
        site.include = (Array(site.include) + files).uniq
      end

      # Categories in use for the current build, memoised per site.
      # { :ids => [category id, ...], :pages => { category id => page } }
      def index(site)
        cached = @index
        return cached[:data] if cached && cached[:site].equal?(site)

        @index = { :site => site, :data => build_index(site) }
        @index[:data]
      end

      # True when this page hosts a category.
      def category_page?(page, site)
        return false if page.nil? || site.nil?

        index(site)[:pages][category_key(page)].equal?(page)
      end

      # Page that hosts the given category, or nil.
      def category_page_for(site, category)
        id = Jekyll::PluginUtils.category_normalize(category)
        return nil if id.nil?

        index(site)[:pages][id]
      end

      # Direct sub categories of a category as [id, page] pairs, in chapter
      # `order` when the category page declares one, by path otherwise.
      def child_categories(site, category)
        id = Jekyll::PluginUtils.category_normalize(category)
        return [] if site.nil? || id.nil?

        data = index(site)
        children = data[:ids].select do |child|
          Jekyll::PluginUtils.category_parent(child) == id
        end
        pairs = children.filter_map do |child|
          page = data[:pages][child]
          [child, page] unless page.nil?
        end
        pairs.sort_by { |_child, page| page_sort_key(page) }
      end

      private

      def build_index(site)
        ids = {}
        (site.pages + site.posts.docs).each do |doc|
          Jekyll::PluginUtils.normalize_list(doc.data["categories"]).each do |raw|
            id = Jekyll::PluginUtils.category_normalize(raw)
            next if id.nil? || !Jekyll::PluginUtils.category_listable?(id)

            ids[id] = true
            # An ancestor only needs a page to be listable as a sub category.
            Jekyll::PluginUtils.category_ancestors(id).each { |ancestor| ids[ancestor] = true }
          end
        end

        # A category page provided by an author introduces its category even
        # when nothing declares it yet.
        provided = Jekyll::Authors.provided_category_pages
        provided.each_value do |id|
          ids[id] = true
          Jekyll::PluginUtils.category_ancestors(id).each { |ancestor| ids[ancestor] = true }
        end

        pages = {}
        site.pages.each do |page|
          key = category_key(page)
          next unless ids.key?(key)
          # A mirrored file is only a category page when Authors says so.
          next if mirrored?(page) && !provided.key?(relative_path(page))

          pages[key] ||= page
        end

        { :ids => ids.keys, :pages => pages }
      end

      def mirrored?(page)
        Jekyll::Authors.registry.key?(relative_path(page))
      end

      # Path of the page without its extension: guides/advanced.md -> guides/advanced.
      def category_key(page)
        relative_path(page).sub(%r!\.[^./]+\z!, "")
      end

      # <li> items for a category: sub categories first, then members.
      def entries(page, site, category = nil)
        id = category || category_for(page, site, nil)
        return [] if id.nil?

        items = child_categories(site, id).map do |_child, child_page|
          link_item(site, child_page, "category-list-child")
        end
        items.concat(members(site, id, page).map { |doc| link_item(site, doc) })
        items
      end

      def link_item(site, doc, css_class = nil)
        klass = css_class.nil? ? "" : %( class="#{css_class}")
        %(<li#{klass}><a href="#{CGI.escapeHTML(doc_url(site, doc))}">) +
          "#{CGI.escapeHTML(display_name(doc))}</a></li>"
      end

      # Category of the current page: explicit argument -> the category this
      # page hosts -> the primary declared category -> inferred from the path.
      def category_for(page, site, explicit = nil)
        value = explicit.to_s.strip
        unless value.empty?
          id = Jekyll::PluginUtils.category_normalize(value)
          return id if !id.nil? && Jekyll::PluginUtils.category_valid?(id)

          return nil
        end
        return nil if page.nil?

        return category_key(page) if category_page?(page, site)

        data = page.respond_to?(:data) ? page.data : page
        raw = data["categories"]
        raw = data["category"] if raw.nil?
        primary, = Jekyll::PluginUtils.primary_category(raw)
        return primary unless primary.nil?

        rel = relative_path(page)
        if rel.include?("/")
          Jekyll::PluginUtils.category_normalize(rel.split("/").first)
        else
          base = File.basename(rel, File.extname(rel))
          base.empty? ? nil : base
        end
      end

      # Direct pages under <category>/ first (by chapter order, then path), then
      # posts in that category (newest first). The current page, category pages
      # and duplicate URLs are skipped.
      def members(site, category, current = nil)
        prefix = "#{category}/"
        current_path = current.nil? ? nil : relative_path(current)

        pages = site.pages.select do |doc|
          rel = relative_path(doc)
          next false if rel == current_path
          next false unless rel.start_with?(prefix)

          rest = rel[prefix.length..]
          next false if rest.nil? || rest.include?("/")

          !category_page?(doc, site)
        end
        pages.sort_by! { |doc| page_sort_key(doc) }

        posts = site.posts.docs.select do |doc|
          next false if current_path && relative_path(doc) == current_path

          Jekyll::PluginUtils.normalize_list(doc.data["categories"]).any? do |raw|
            Jekyll::PluginUtils.category_normalize(raw) == category
          end
        end
        posts.sort_by! { |doc| post_date(doc) || Time.at(0) }
        posts.reverse!

        seen = {}
        (pages + posts).select do |doc|
          url = doc_url(site, doc)
          next false if seen[url]

          seen[url] = true
        end
      end

      # Pages follow the chapter `order` when present (ordered pages first, in
      # ascending order); the path keeps the remaining entries deterministic.
      def page_sort_key(doc)
        segments = Jekyll::PluginUtils.order_segments(doc.data["order"])
        segments.nil? ? [1, [], relative_path(doc)] : [0, segments, relative_path(doc)]
      end

      def post_date(doc)
        value = doc.respond_to?(:date) ? doc.date : doc["date"]
        return nil if value.nil?
        return value if value.respond_to?(:strftime)

        Jekyll::Utils.parse_date(value.to_s)
      rescue StandardError
        nil
      end

      def relative_path(doc)
        rel = doc.respond_to?(:relative_path) ? doc.relative_path : doc["path"]
        rel.to_s.tr("\\", "/").delete_prefix("/")
      end

      # Display name: front matter title first, filename (without extension) as
      # the fallback.
      def display_name(doc)
        data = doc.respond_to?(:data) ? doc.data : doc
        title = data["title"].to_s.strip
        return title unless title.empty?

        File.basename(relative_path(doc), File.extname(relative_path(doc)))
      end

      def doc_url(site, doc)
        url = doc.respond_to?(:url) ? doc.url : doc["url"]
        url = url.to_s
        base = site.respond_to?(:baseurl) ? site.baseurl.to_s : ""
        url = "#{base}#{url}" unless base.empty? || url.start_with?(base)
        Jekyll::URL.escape_path(url)
      end
    end

    class Tag < Liquid::Tag
      def initialize(tag_name, markup, tokens)
        super
        @category = markup.to_s.strip
      end

      def render(context)
        Jekyll::CategoryList.render(
          context.registers[:page],
          context.registers[:site],
          @category
        )
      end
    end
  end
end

Liquid::Template.register_tag("category_list", Jekyll::CategoryList::Tag)

Jekyll::Hooks.register :site, :after_reset do |site|
  Jekyll::CategoryList.allow_listing_pages(site)
end

Jekyll::Hooks.register :pages, :pre_render do |page, _payload|
  Jekyll::CategoryList.inject(page)
end
