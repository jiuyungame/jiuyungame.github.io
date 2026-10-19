module Jekyll
  # Collects the pages that declare a numeric `main_part` front matter value and
  # exposes them as site.data['main_part_page'], ordered by that value
  # descending. _layouts/home.html uses the list for the "Sections" block.
  class MainPart < Generator
    safe true

    def generate(site)
      pages = {}
      site.pages.each do |page|
        value = page.data["main_part"]
        next if value.nil?

        pages[value] = page
      end

      sorted = pages.sort_by { |key, _page| -key.to_i }
      site.data["main_part_page"] = sorted.map(&:last) unless sorted.empty?
    end
  end
end
