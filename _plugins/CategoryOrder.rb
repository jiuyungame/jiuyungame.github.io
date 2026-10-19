require 'time'
require 'cgi'

module Jekyll
  # Orders pages inside a category and renders chapter navigation.
  #
  # Categories nest (guides/advanced). Each document joins exactly one chapter:
  # its primary category, the deepest one it declares. A document that declares
  # several categories still appears in every category's member list (see
  # _plugins/CategoryList.rb) but only gets previous/next links from one chain,
  # so the single-valued navigation data can never be written twice.
  #
  # Pages that share a category and declare an `order` are put into one sequence
  # (posts keep Jekyll's own date based neighbours, see _layouts/post.html):
  #   - `order` accepts hierarchical numbers such as 2, 2.1, 2.2.1; segments are
  #     compared one by one, so 1.10 sorts after 1.2;
  #   - a document with `order: 0` is the chapter root: every other member gets
  #     data['root'] pointing at it (the "Back to category" link) and
  #     data['parent'] pointing at its nearest ancestor (the "Back to parent"
  #     link). The root itself is not part of the prev/next chain but receives
  #     data['toc_html'] for the whole chapter, plus an entry per sub category;
  #   - the root of a sub category also gets data['parent'] pointing at the
  #     category page of its parent category;
  #   - a document whose order is a prefix of other members' orders (1 for 1.1,
  #     1.2) also receives a nested data['toc_html'] for those descendants; its
  #     own position in the chain is unchanged;
  #   - members are chained in ascending order into data['prev'] / data['next'],
  #     rendered by _includes/page-nav.html; the table of contents is rendered by
  #     the layouts from page.toc_html.
  #
  # Category pages are navigation hubs, not chapter members: the chain logic
  # skips them, so they never receive prev/next/root/toc data. They only get a
  # data['parent'] link to their parent category page (or to the home page when
  # top level); every other document gets data['root'] pointing one level up.
  #
  # Category pages also use the order when listing their members, see
  # _plugins/CategoryList.rb.
  class CategoryOrderGenerator < Generator
    safe true
    priority :low # after other generators (TagsPage etc.) so site.pages is complete

    def generate(site)
      groups = Hash.new { |h, k| h[k] = [] }
      site.pages.each do |doc|
        next if Jekyll::CategoryList.category_page?(doc, site)

        primary, others = Jekyll::PluginUtils.primary_category(doc.data['categories'])
        next if primary.nil?

        warn_ambiguous_chain(doc, primary, others)
        groups[primary] << doc
      end

      groups.each do |category, members|
        ordered = members.select { |doc| !doc.data['order'].nil? }
        next if ordered.empty?

        toc = ordered.find { |doc| self.class.segments(doc.data['order']) == [0] }
        chain = ordered.reject { |doc| doc == toc }
        chain.sort_by! { |doc| self.class.segments(doc.data['order']) }

        chain.each_index do |i|
          doc = chain[i]
          doc.data['prev'] = chain[i - 1] unless i.zero?
          doc.data['next'] = chain[i + 1] if i < chain.size - 1
          doc.data['root'] = toc if toc
        end

        # Parent link: the longest proper prefix of this order (1.1.1 -> 1.1).
        # Top-level documents have no parent link.
        chain.each do |doc|
          seg = self.class.segments(doc.data['order'])
          parent = chain.select { |m| self.class.proper_prefix?(self.class.segments(m.data['order']), seg) }
                        .max_by { |m| self.class.segments(m.data['order']).size }
          doc.data['parent'] = parent if parent
        end

        sections = Jekyll::CategoryList.child_categories(site, category).map { |_id, page| page }

        if toc
          # order: 0 root page: list every chapter member, then the sub categories.
          toc.data['toc_html'] = self.class.toc_html_of(site, chain, sections)
          self.class.link_parent_category(site, category, toc)
        end

        # Any prefix document: list the descendants it contains.
        chain.each do |doc|
          seg = self.class.segments(doc.data['order'])
          descendants = chain.select { |m| self.class.proper_prefix?(seg, self.class.segments(m.data['order'])) }
          doc.data['toc_html'] = self.class.toc_html_of(site, descendants) unless descendants.empty?
        end
      end

      link_up(site)
      link_category_pages(site)
    end

    # Every document links back up to its category page: the chapter root when the
    # category has one (the chain logic above already set it), otherwise the
    # category page itself. Posts never have a chapter root.
    def link_up(site)
      (site.pages + site.posts.docs).each do |doc|
        next if Jekyll::CategoryList.category_page?(doc, site)

        page = Jekyll::CategoryList.parent_category_page(site, doc)
        next if page.nil?

        doc.data['root'] ||= page
      end
    end

    # Category pages link to their parent category page, or to the home page when
    # they are top level. A section that was merged into a single page is no
    # longer a category page, so it gets the home link through `main_part`.
    def link_category_pages(site)
      home = home_page(site) || { 'url' => '/' }

      site.pages.each do |page|
        id = Jekyll::CategoryList.hosted_category(page, site)
        if id.nil?
          next if page.data['main_part'].nil? || page.data['parent'] || page.data['root']

          page.data['parent'] = home
          page.data['parent_label'] = 'Home'
          next
        end

        parent_id = Jekyll::PluginUtils.category_parent(id)
        if parent_id.nil?
          page.data['parent'] = home
          page.data['parent_label'] = 'Home'
          next
        end

        parent_page = Jekyll::CategoryList.category_page_for(site, parent_id)
        page.data['parent'] = parent_page unless parent_page.nil?
      end
    end

    # The home page, used as the parent of a top level category page.
    def home_page(site)
      site.pages.find { |page| page.url.to_s == '/' }
    end

    # A document with several categories and an order can only sit in one
    # chain; say so instead of silently dropping it from the others.
    def warn_ambiguous_chain(doc, primary, others)
      return if others.empty? || doc.data['order'].nil?

      path = doc.respond_to?(:relative_path) ? doc.relative_path : doc['path']
      Jekyll.logger.warn "CategoryOrder:",
                         "#{path} declares several categories; it joins the " \
                         "'#{primary}' chapter only (also declares: #{others.join(', ')})"
    end

    # Sub category root: "Back to parent" points at the parent category page.
    def self.link_parent_category(site, category, doc)
      return if doc.nil? || doc.data['parent']

      parent_id = Jekyll::PluginUtils.category_parent(category)
      return if parent_id.nil?

      page = Jekyll::CategoryList.category_page_for(site, parent_id)
      doc.data['parent'] = page if page
    end

    # Normalise an order value into integer segments:
    # 2 -> [2], "2.2.1" -> [2, 2, 1], 2.0 -> [2].
    def self.segments(order)
      Jekyll::PluginUtils.order_segments(order)
    end

    # Table of contents for a chapter root: the numbered members followed by one
    # entry per sub category.
    def self.toc_html_of(site, docs, sections = [])
      numbered = docs.empty? ? '' : render_list(build_tree(toc_items(site, docs)))
      extra = sections.map do |page|
        %(<li class="toc-category"><a href="#{CGI.escapeHTML(absolute_url(site, page))}">) +
          "#{CGI.escapeHTML(page.data['title'].to_s)}</a></li>"
      end

      return numbered if extra.empty?
      return "<ul>#{extra.join}</ul>" if numbered.empty?

      numbered.sub(%r!</ul>\s*\z!, "#{extra.join}</ul>")
    end

    def self.toc_items(site, docs)
      items = docs.map do |doc|
        seg = segments(doc.data['order'])
        {
          :seg     => seg,
          :display => seg.join('.'),
          :title   => CGI.escapeHTML(doc.data['title'].to_s),
          :url     => CGI.escapeHTML(absolute_url(site, doc))
        }
      end
      items.sort_by! { |i| i[:seg] }
      items
    end

    # Jekyll's page URLs do not include baseurl; add it for project pages.
    def self.absolute_url(site, doc)
      url = doc.url.to_s
      base = site.respond_to?(:baseurl) ? site.baseurl.to_s : ""
      return url if base.empty? || url.start_with?(base)

      "#{base}#{url}"
    end

    # Build a nested tree from sorted items (a parent segment is a prefix of its
    # children's segments).
    def self.build_tree(items)
      root = { :seg => [], :children => [] }
      stack = [root]
      items.each do |item|
        node = {
          :seg      => item[:seg],
          :display  => item[:display],
          :title    => item[:title],
          :url      => item[:url],
          :children => []
        }
        stack.pop while stack.size > 1 && !proper_prefix?(stack.last[:seg], node[:seg])
        stack.last[:children] << node
        stack << node
      end
      root[:children]
    end

    def self.proper_prefix?(a, b)
      a.size < b.size && b[0, a.size] == a
    end

    def self.render_list(nodes)
      return '' if nodes.empty?

      html = +"<ul>"
      nodes.each do |n|
        html << "<li><a href=\"#{n[:url]}\">#{n[:display]} #{n[:title]}</a>"
        html << render_list(n[:children]) unless n[:children].empty?
        html << "</li>"
      end
      html << "</ul>"
    end
  end
end
