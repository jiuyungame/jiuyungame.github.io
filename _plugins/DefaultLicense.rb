module Jekyll
  # Inherits a license inside a category group.
  #
  # Documents with `layout: article` that do not set `license` themselves take
  # the license of their group's root page (`order: 0`, same primary category).
  # When that category has no root page with a license, its ancestors are
  # consulted, so a sub category inherits from the parent category. Category
  # pages are not members and are left alone. When nothing is found,
  # _includes/license.html falls back to site.license.
  class DefaultLicenseGenerator < Generator
    safe true
    priority :low

    def generate(site)
      groups = Hash.new { |h, k| h[k] = [] }
      (site.posts.docs + site.pages).each do |doc|
        next if Jekyll::CategoryList.category_page?(doc, site)

        primary, = Jekyll::PluginUtils.primary_category(doc.data['categories'])
        next if primary.nil?

        groups[primary] << doc
      end

      groups.each do |category, members|
        license = license_for(groups, category)
        next if license.nil?

        members.each do |doc|
          next unless doc.data['layout'] == 'article'

          doc.data['license'] ||= license
        end
      end
    end

    # Root licence of the category, falling back to its ancestors. `fetch` keeps
    # the groups hash unchanged while it is being iterated.
    def license_for(groups, category)
      ([category] + Jekyll::PluginUtils.category_ancestors(category)).each do |id|
        root = groups.fetch(id, []).find { |member| root_order?(member.data['order']) }
        return root.data['license'] if root && root.data['license']
      end
      nil
    end

    def root_order?(order)
      return false if order.nil?

      order.to_s.split('.').map(&:to_i) == [0]
    end
  end
end
