module Jekyll
  # Small shared helpers for the plugins in this template.
  module PluginUtils
    module_function

    # Directory names that can never be a category (they belong to the site's
    # own structure).
    CATEGORY_RESERVED = %w[tmp authors authors-src].freeze

    # Category ids that exist for listing only. They may carry a category page
    # and be matched by CategoryList, but they are never a valid mirror target,
    # so nothing can be written into a directory that Jekyll reserves.
    LISTING_CATEGORIES = %w[_posts].freeze

    # Normalise a front matter list (categories / tags) into an array of
    # non-empty, unique strings.
    #
    #   nil               -> []
    #   "a b"             -> ["a", "b"]          (Jekyll's space separated form)
    #   ["a", ["b"]]      -> ["a", "b"]
    #   ["a", " ", "a"]   -> ["a"]
    def normalize_list(value)
      return [] if value.nil?

      values = value.is_a?(String) ? value.split(%r!\s+!) : Array(value)
      values.flatten
            .map { |item| item.to_s.strip }
            .reject(&:empty?)
            .uniq
    end

    # Normalise an `order` value into integer segments:
    # 2 -> [2], "2.2.1" -> [2, 2, 1], 2.0 -> [2]. Returns nil when unset.
    def order_segments(value)
      return nil if value.nil? || value.to_s.strip.empty?

      number = value.is_a?(Float) && value == value.to_i ? value.to_i : value
      number.to_s.split(".").map(&:to_i)
    end

    # ---------------------------------------------------------------------
    # Categories
    #
    # A category is a slash separated path such as "guides" or
    # "guides/advanced". Categories nest: "guides/advanced" is a child of
    # "guides". The rules below are the single implementation of what a valid
    # category looks like; the plugins never test separators themselves.
    # ---------------------------------------------------------------------

    # Canonical form of a category value: trims the outer slashes, folds
    # repeated separators, treats a backslash as a separator and strips
    # whitespace around each segment.
    #
    #   " /guides//advanced/ " -> "guides/advanced"
    #   ""                     -> nil
    def category_normalize(value)
      return nil if value.nil?

      segments = value.to_s.tr("\\", "/").split("/")
                      .map(&:strip)
                      .reject(&:empty?)
      return nil if segments.empty?

      segments.join("/")
    end

    # "guides/advanced" -> ["guides", "advanced"]; unset -> [].
    def category_segments(value)
      id = category_normalize(value)
      return [] if id.nil?

      id.split("/")
    end

    # One path segment: no leading _ or ., no reserved name, no characters
    # Windows rejects, no trailing space or dot.
    def category_segment_ok?(segment)
      return false if segment.nil?

      seg = segment.to_s
      return false if seg.empty? || seg == "." || seg == ".."
      return false if seg.start_with?("_", ".")
      return false if seg.match?(%r![<>:"|?*\x00-\x1f]!)
      return false if seg.end_with?(" ", ".")
      return false if CATEGORY_RESERVED.include?(seg)

      true
    end

    # True when the value normalises to a usable category id.
    def category_valid?(value)
      id = category_normalize(value)
      return false if id.nil?

      id.split("/").all? { |seg| category_segment_ok?(seg) }
    end

    # True when the value can be used to group documents into a list. Wider than
    # category_valid?: the listing only categories (see LISTING_CATEGORIES) are
    # listable but never a valid mirror target.
    def category_listable?(value)
      id = category_normalize(value)
      return false if id.nil?

      LISTING_CATEGORIES.include?(id) || category_valid?(id)
    end

    # "guides/advanced" -> "guides"; top level -> nil.
    def category_parent(value)
      segments = category_segments(value)
      return nil if segments.size < 2

      segments[0..-2].join("/")
    end

    # Ancestors nearest first: "a/b/c" -> ["a/b", "a"].
    def category_ancestors(value)
      segments = category_segments(value)
      return [] if segments.size < 2

      (1...segments.size).to_a.reverse.map { |n| segments[0, n].join("/") }
    end

    def category_depth(value)
      category_segments(value).size
    end

    # Collapse a categories list into one primary category plus the rest.
    #
    # The chain, licence and table-of-contents data are single valued, so a
    # document needs exactly one category for those. Ordering is deterministic:
    # the deepest category wins, ties break on the id, never on the order the
    # author happened to write.
    #
    # Returns [primary, others]; [nil, []] when nothing usable is declared.
    def primary_category(value)
      ids = normalize_list(value)
            .map { |raw| category_normalize(raw) }
            .compact
            .select { |id| category_valid?(id) }
            .uniq
      return [nil, []] if ids.empty?

      ordered = ids.sort_by { |id| [-category_depth(id), id] }
      [ordered.first, ordered.drop(1)]
    end

    # Value of the `category_page` front matter switch.
    def category_page_flag?(data)
      return false unless data.is_a?(Hash)

      value = data["category_page"]
      value == true || value.to_s.strip.casecmp("true").zero?
    end
  end
end
