require "digest"
require "json"
require "fileutils"
require "time"

module Jekyll
  # Per-author content mirror.
  #
  # Every direct sub-directory of `authors.source` (default: authors-src/) is one
  # author. Before Jekyll reads the site, the contents are mirrored into the
  # positions Jekyll expects:
  #
  #   authors-src/<author>/
  #     <content page> with categories -> <category>/<title slug><ext>
  #                                       (one copy per usable category)
  #     <anything else>                -> authors/<author>/<relative path>
  #     _posts/**                      -> _posts/<author>/**
  #     _drafts/**                     -> _drafts/<author>/**
  #     _includes/**                   -> _includes/<author>/**
  #     _layouts/**                    -> _layouts/<author>/**
  #     _sass/**                       -> _sass/<author>/**
  #     _data/**                       -> _data/<author>/**
  #     _plugins/**                    -> skipped (plugins load before the mirror)
  #
  # Category rules:
  #   - A category is usable only when its category page exists: <category>.md,
  #     .markdown, .html or .htm, relative to the site root.
  #     Copies for missing categories are skipped with a warning; when none of a
  #     page's categories is usable the page falls back to authors/<author>/...
  #   - Categories nest through a slash path: categories: [guides/advanced]
  #     produces guides/advanced/<title>.md and its category page is
  #     guides/advanced.md. categories: [math, functions] still produces two
  #     sibling copies.
  #   - An author can provide a category page from their own folder by setting
  #     `category_page: true`. The category comes from `categories` or, when
  #     that is absent, from the folder path below the author folder:
  #       <author>/guides/advanced/index.md -> guides/advanced.md
  #     Only nested categories are accepted (owners create the top level), the
  #     file produces no member copy of its own category, and a category page
  #     maintained by the site owner always wins.
  #   - <title> is the front matter `title` run through Jekyll's slugify
  #     (Unicode is preserved); when it is missing or empty the source filename
  #     is used. The source extension is kept.
  #   - While a copy is rendered its page.categories are narrowed to that copy's
  #     category, so CategoryOrder / DefaultLicense never see the same page twice.
  #     Category pages are never narrowed.
  #   - Author pages are ordinary category pages: a page with
  #     `categories: [author]` lands in author/<title>.md, provided the site
  #     owner created author.md. There is no special-casing of author.md.
  #   - Category pages get an automatic member list, see
  #     _plugins/CategoryList.rb and the {% category_list %} tag. Set
  #     `category_list: false` to opt out on a single page.
  #
  # Mirrored files are removed again after the build (at_exit). Set
  # `authors.keep_mirror: true` to keep them. Files that this plugin did not
  # create are never overwritten or deleted: a sha256 manifest tells external
  # edits apart from files the plugin wrote.
  #
  # Optional _config.yml:
  #
  #   authors:
  #     source: authors-src   # author folders (relative to the site root)
  #     page_dir: authors     # target for content without a usable category
  #     keep_mirror: false    # true = keep the mirrored files after the build
  module Authors
    DEFAULTS = {
      "source"      => "authors-src",
      "page_dir"    => "authors",
      "keep_mirror" => false,
    }.freeze

    MANIFEST_NAME      = "authors-mirror.json"
    CATEGORY_FILE_EXTS = %w[.md .markdown .html .htm].freeze

    POST_DIR    = "_posts"
    DRAFT_DIR   = "_drafts"
    PLUGIN_DIR  = "_plugins"
    INCLUDE_DIR = "_includes"

    class << self
      # Target relative path -> author name, used by {% include_author %}.
      # Rebuilt on every build.
      def registry
        @registry ||= {}
      end

      # Category pages this build took from an author folder, as
      # { relative path => category id }. CategoryList and friends treat these
      # files as category pages even though they are mirrored, not committed.
      def provided_category_pages
        @provided_category_pages ||= {}
      end

      # :site, :after_reset hook. Runs before the site is read, on every build
      # (including `jekyll serve` rebuilds).
      #
      # Two passes: the first collects what every author file declares, so a
      # category page provided by an author counts as usable even though it does
      # not exist on disk yet; the second maps the files.
      def mirror(site)
        cfg = config_for(site)
        src = source_dir(site, cfg)
        @page_dir = cfg["page_dir"].to_s
        @provided_category_pages = {}
        warn_legacy_source(site, cfg, src)

        expected = {}
        mapping = {}
        target_categories = {}
        authors = []
        skipped = []
        report = {}
        previous = read_manifest(site)
        plan = empty_plan

        if src && File.directory?(src)
          hide_source!(site, src)

          authors = author_dirs(src)
          authors.each { |author| warn_unsafe_author(author) }

          entries = author_entries(src, authors, site)
          plan = build_plan(entries, site, previous, report)

          entries.each do |entry|
            author = entry[:author]
            targets = targets_for(author, entry[:rel], entry[:abs], cfg, site,
                                  entry[:data], report, plan)
            if targets.nil?
              skipped << posix_join(author, entry[:rel])
              next
            end
            targets.each do |target_entry|
              target = target_entry[:target]
              if expected.key?(target)
                Jekyll.logger.warn "Authors:",
                                   "Duplicate mapping target, skipping " \
                                   "#{posix_join(author, entry[:rel])} -> #{target}"
                next
              end
              expected[target] = entry[:abs]
              mapping[target] = author
              target_categories[target] = target_entry[:category]
            end
          end
        end

        log_report(report)
        unless skipped.empty?
          Jekyll.logger.warn "Authors:",
                             "Skipped #{skipped.size} author plugin file(s) " \
                             "(authors cannot ship Jekyll plugins): " \
                             "#{skipped.first(3).join(', ')}#{skipped.size > 3 ? ' ...' : ''}"
        end

        owned = sync(site, expected, previous)
        write_manifest(site, owned)

        routed = owned.keys.count { |rel| target_categories[rel] }
        @registry = mapping.select { |rel, _author| owned.key?(rel) }
        @provided_category_pages = plan[:author_paths].select { |rel, _id| owned.key?(rel) }
        @category_by_target = target_categories.select { |rel, cat| cat && owned.key?(rel) }
        track(site, owned, cfg)

        if !expected.empty? || !previous.empty?
          message = "Mapped #{authors.size} author(s) / #{owned.size} file(s)"
          unless routed.zero?
            categories = @category_by_target.values.uniq.first(3).join(", ")
            message += ", #{routed} category copy(ies) (#{categories})"
          end
          unless @provided_category_pages.empty?
            ids = @provided_category_pages.values.uniq.first(3).join(", ")
            message += ", #{@provided_category_pages.size} category page(s) (#{ids})"
          end
          Jekyll.logger.info "Authors:", message
        end
        nil
      rescue StandardError => e
        Jekyll.logger.warn "Authors:", "Mapping failed: #{e.class}: #{e.message}"
        Jekyll.logger.debug "Authors:", Array(e.backtrace).first(5).join("\n")
        nil
      end

      # :site, :post_read hook: narrow every category copy to its own category.
      def narrow_category_groups(site)
        by_target = @category_by_target
        return if by_target.nil? || by_target.empty?

        site.pages.each do |page|
          key = normalize_rel(page.relative_path).delete_prefix("/")
          category = by_target[key]
          next if category.nil?

          page.data["categories"] = [category]
        end
      rescue StandardError => e
        Jekyll.logger.warn "Authors:", "Failed to narrow category copies: #{e.class}: #{e.message}"
      end

      # Used by {% include_author %}: find the author of the current document.
      def author_for(page)
        return nil if page.nil?

        path = begin
          page["path"] || page["relative_path"]
        rescue StandardError
          nil
        end
        return nil if path.nil?

        key = normalize_rel(path.to_s).delete_suffix("/#excerpt")
        registry[key] || author_from_path(key)
      end

      # Targets for one source file (nil = skip the whole file).
      # Returns [{ :target => relative path, :category => category or nil,
      #            :category_page => category id or nil }, ...].
      #
      # `plan` carries the two-pass build state (see build_plan); without it the
      # function falls back to the single-pass behaviour of asking the disk.
      def targets_for(author, rel, abs_path = nil, cfg = DEFAULTS, site = nil,
                      data = nil, report = nil, plan = nil)
        cfg = DEFAULTS.merge(cfg || {})
        report ||= {}
        rel = normalize_rel(rel)
        top, rest = rel.split("/", 2)
        fallback = [{ :target => posix_join(cfg["page_dir"].to_s, author, rel),
                      :category => nil }]

        if !rest.nil? && top.start_with?("_")
          return nil if top == PLUGIN_DIR

          target = underscore_target(author, top, rest, abs_path, site, data)
          return [{ :target => target, :category => nil }]
        end

        if !plan.nil? && Jekyll::PluginUtils.category_page_flag?(data)
          key = posix_join(author, rel)
          id = plan[:accepted][key]
          if id
            return [{ :target => "#{id}#{File.extname(rel)}", :category => nil,
                      :category_page => id }]
          end

          (report[:cp_fallback] ||= {})[key] = true
          return fallback
        end

        categories = categories_of(data, report)
        unless categories.empty?
          usable = []
          categories.each do |raw|
            id = Jekyll::PluginUtils.category_normalize(raw)
            if id.nil? || !Jekyll::PluginUtils.category_valid?(id)
              (report[:invalid] ||= {})[raw.to_s] = true
              next
            end

            available = plan.nil? ? !category_page_file(site, id).nil? : plan[:usable].key?(id)
            if available
              usable << id
            else
              (report[:missing] ||= {})[id] = true
            end
          end

          unless usable.empty?
            slug = title_slug(data, rel, site)
            if slug
              members = usable.map do |id|
                {
                  :target   => posix_join(id, "#{slug}#{File.extname(rel)}"),
                  :category => id,
                }
              end
              members = drop_shadowed(members, plan, report)
              return members unless members.empty?
            end
          end

          report[:fallback] = report.fetch(:fallback, 0) + 1
        end

        fallback
      end

      # Called from at_exit: delete files written by this build and prune empty
      # directories that were left behind.
      def cleanup_all
        states = @states
        return if states.nil? || states.empty?

        states.each_value do |state|
          next if state[:keep]

          state[:owned].each do |rel, digest|
            path = state[:site].in_source_dir(rel)
            next unless File.file?(path)

            unless digest_ok?(path, digest)
              Jekyll.logger.warn "Authors:",
                                 "Cleanup: keeping #{rel} because it was modified externally"
              next
            end
            File.delete(path)
          end
          prune_dirs(state[:site], state[:owned].keys)
          File.delete(state[:manifest]) if File.file?(state[:manifest])
        end
      rescue StandardError => e
        Jekyll.logger.warn "Authors:", "Failed to clean up mirrored files: #{e.class}: #{e.message}"
      ensure
        @states = {}
      end

      private

      def config_for(site)
        custom = site.config["authors"]
        custom.is_a?(Hash) ? DEFAULTS.merge(custom) : DEFAULTS
      end

      def source_dir(site, cfg)
        value = cfg["source"].to_s.strip
        return nil if value.empty?
        return File.expand_path(value) if absolute_path?(value)

        site.in_source_dir(value)
      end

      def absolute_path?(value)
        value.start_with?("/", "\\") || value.match?(%r!\A[a-zA-Z]:[\\/]!)
      end

      # Exclude the author source from the site output: the originals must not be
      # published as regular pages or static files. A new array is assigned
      # instead of mutating it, so `jekyll serve` keeps watching the folder.
      def hide_source!(site, src)
        rel = relative_to(site.source, src)
        return unless rel

        site.exclude = (Array(site.exclude) + [rel]).uniq
      end

      # Warn when a legacy tmp/ folder would now be published as normal content.
      def warn_legacy_source(site, cfg, src)
        legacy = site.in_source_dir("tmp")
        return unless File.directory?(legacy)
        return if src && normalize_rel(src) == normalize_rel(legacy)

        Jekyll.logger.warn "Authors:",
                           "Author source is set to #{cfg["source"]} but a tmp/ folder still " \
                           "exists at the site root; tmp/ will be published as normal site " \
                           "content - move or delete it"
      end

      def author_dirs(src)
        Dir.children(src).sort.select do |entry|
          next false if entry.start_with?(".", "_")

          File.directory?(File.join(src, entry))
        end
      end

      def each_file(dir, prefix = nil, &block)
        Dir.children(dir).sort.each do |entry|
          next if entry.start_with?(".") || entry.end_with?("~")

          path = File.join(dir, entry)
          next if File.symlink?(path)

          rel = prefix ? posix_join(prefix, entry) : entry
          if File.directory?(path)
            each_file(path, rel, &block)
          elsif File.file?(path)
            block.call(rel, path)
          end
        end
      end

      # -------------------------------------------------------------------
      # Two-pass planning
      # -------------------------------------------------------------------

      def empty_plan
        { :usable => {}, :claims => {}, :accepted => {},
          :page_paths => {}, :author_paths => {} }
      end

      # Every author file with its front matter, read once for both passes.
      def author_entries(src, authors, site)
        entries = []
        authors.each do |author|
          each_file(File.join(src, author)) do |rel, abs|
            entries << {
              :author => author,
              :rel    => rel,
              :abs    => abs,
              :data   => front_matter(abs, site),
            }
          end
        end
        entries
      end

      # Decide which categories are usable and which author files become
      # category pages. Runs before anything is written, so a category page
      # provided by an author is known before the copies that need it.
      def build_plan(entries, site, previous, report)
        plan = empty_plan

        entries.each do |entry|
          next unless entry[:data].is_a?(Hash)

          declared_ids(entry[:data]).each { |id| plan[:usable][id] = true }

          next unless Jekyll::PluginUtils.category_page_flag?(entry[:data])

          if special_dir?(entry[:rel])
            (report[:cp_special] ||= {})[posix_join(entry[:author], entry[:rel])] = true
            next
          end

          key = posix_join(entry[:author], entry[:rel])
          id, others = category_page_id(entry[:rel], entry[:data])

          if id.nil?
            (report[:cp_no_id] ||= {})[key] = true
            next
          end
          unless Jekyll::PluginUtils.category_valid?(id)
            (report[:cp_invalid] ||= {})[id] = true
            next
          end
          if Jekyll::PluginUtils.category_depth(id) < 2
            (report[:cp_top_level] ||= {})[id] = true
            next
          end

          (report[:cp_multi] ||= {})[id] = true unless others.empty?

          owner = owner_category_page_rel(site, id, previous)
          if owner
            (report[:cp_owner] ||= {})[id] = owner
            next
          end

          if plan[:claims].key?(id)
            (report[:cp_duplicate] ||= {})[id] = plan[:claims][id][:author]
            next
          end

          plan[:claims][id] = entry
          plan[:accepted][key] = id
          plan[:usable][id] = true
        end

        # A declared category is only usable when a category page exists for it:
        # either the owner's file or an author provided one.
        plan[:usable].delete_if do |id, _flag|
          next false if plan[:claims].key?(id)

          owner_category_page_rel(site, id, previous).nil?
        end

        plan[:usable].each_key do |id|
          owner = owner_category_page_rel(site, id, previous)
          if owner
            plan[:page_paths][owner] = id
          elsif (claim = plan[:claims][id])
            rel = "#{id}#{File.extname(claim[:rel])}"
            plan[:page_paths][rel] = id
            plan[:author_paths][rel] = id
          end
        end

        plan
      end

      # _posts/, _drafts/ and friends: `category_page` does not apply there.
      def special_dir?(rel)
        top, rest = normalize_rel(rel).split("/", 2)
        !rest.nil? && top.start_with?("_")
      end

      # Category an author provided category page belongs to: the front matter
      # first, then the folder path below the author folder.
      def category_page_id(rel, data)
        primary, others = Jekyll::PluginUtils.primary_category(data["categories"])
        return [primary, others] unless primary.nil?

        dir = File.dirname(normalize_rel(rel))
        return [nil, []] if dir == "." || dir.empty?

        [Jekyll::PluginUtils.category_normalize(dir), []]
      end

      # Valid categories declared by a file's front matter.
      def declared_ids(data)
        raw = data["categories"]
        raw = data["category"] if raw.nil?
        Jekyll::PluginUtils.normalize_list(raw).filter_map do |value|
          id = Jekyll::PluginUtils.category_normalize(value)
          id if id && Jekyll::PluginUtils.category_valid?(id)
        end.uniq
      end

      # Existing category page maintained outside the mirror. Manifest entries
      # are left over mirrors, not owner content.
      def owner_category_page_rel(site, id, previous)
        return nil if site.nil? || id.nil?

        CATEGORY_FILE_EXTS.each do |ext|
          rel = "#{id}#{ext}"
          next if previous.key?(rel)

          return rel if File.file?(site.in_source_dir(rel))
        end
        nil
      end

      # A member copy must never land on a category page path.
      def drop_shadowed(members, plan, report)
        return members if plan.nil?

        members.reject do |member|
          next false unless plan[:page_paths].key?(member[:target])

          (report[:shadowed] ||= {})[member[:target]] = true
          true
        end
      end

      def underscore_target(author, top, rest, abs_path, site, data)
        name = File.basename(rest)
        dir = File.dirname(rest)
        if top == POST_DIR && abs_path
          prefix = date_prefix(abs_path, name, site, data)
          name = "#{prefix}-#{name}" if prefix
        end
        posix_join(top, author, dir == "." ? nil : dir, name)
      end

      # categories / category front matter -> array of strings (via PluginUtils).
      def categories_of(data, report = nil)
        return [] unless data.is_a?(Hash)

        raw = data["categories"]
        report[:string_categories] = true if report && raw.is_a?(String)
        raw = data["category"] if raw.nil?

        Jekyll::PluginUtils.normalize_list(raw)
      end

      # A category page is named after the category id, so nesting works the
      # same way as for single level categories: guides/advanced.md.
      def category_page_file(site, category)
        return nil if site.nil?

        CATEGORY_FILE_EXTS.map { |ext| site.in_source_dir("#{category}#{ext}") }
                          .find { |path| File.file?(path) }
      end

      # <title-name>: front matter title -> Jekyll slugify; fall back to the
      # source filename when there is no usable title.
      def title_slug(data, rel, site)
        title = data.is_a?(Hash) ? data["title"].to_s.strip : ""
        unless title.empty?
          mode = site.respond_to?(:config) ? site.config["slugify_mode"] : nil
          slug = begin
            Jekyll::Utils.slugify(title, :mode => (mode || "default").to_s).to_s
          rescue StandardError
            ""
          end
          return slug unless slug.empty? || slug.match?(%r![/\\]!)
        end

        base = File.basename(rel, File.extname(rel)).to_s
        return nil if base.empty?

        base
      end

      # Sync: remove stale mirrors, then copy new/changed files (sha256 ownership).
      #
      # A file the manifest does not list was not created by this plugin, so it
      # is never written to and never claimed: claiming it would make at_exit
      # delete somebody else's file later on.
      def sync(site, expected, previous)
        stale = previous.keys - expected.keys
        stale.each { |rel| remove_target(site, rel, previous[rel]) }
        prune_dirs(site, stale)

        owned = {}
        expected.keys.sort.each do |rel|
          src_path = expected[rel]
          dst = site.in_source_dir(rel)
          begin
            if File.file?(dst)
              if previous.key?(rel)
                if digest_ok?(dst, previous[rel])
                  copy_if_changed(src_path, dst)
                  owned[rel] = digest_of(src_path)
                else
                  Jekyll.logger.warn "Authors:", "Target was modified externally, skipping #{rel}"
                end
              else
                Jekyll.logger.warn "Authors:",
                                   "Target exists and is not managed by this plugin, skipping " \
                                   "#{rel} (delete it and rebuild to map)"
              end
            else
              write_copy(src_path, dst)
              owned[rel] = digest_of(src_path)
            end
          rescue StandardError => e
            Jekyll.logger.warn "Authors:", "Failed to map #{rel}: #{e.message}"
          end
        end
        owned
      end

      def remove_target(site, rel, digest = nil)
        path = site.in_source_dir(rel)
        return unless File.file?(path)

        unless digest_ok?(path, digest)
          Jekyll.logger.warn "Authors:", "Kept stale mirror #{rel} because it was modified externally"
          return
        end

        File.delete(path)
        Jekyll.logger.debug "Authors:", "Removed stale mirror #{rel}"
      rescue StandardError => e
        Jekyll.logger.warn "Authors:", "Failed to remove stale mirror #{rel}: #{e.message}"
      end

      def copy_if_changed(src, dst)
        return if File.size(dst) == File.size(src) && File.mtime(dst) >= File.mtime(src)

        write_copy(src, dst)
      end

      def write_copy(src, dst)
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(src, dst, :preserve => true)
      end

      def digest_of(path)
        Digest::SHA256.file(path).hexdigest
      rescue StandardError
        nil
      end

      def digest_ok?(path, expected)
        return true if expected.nil?

        File.file?(path) && digest_of(path) == expected
      end

      def front_matter(abs_path, site)
        return nil if abs_path.nil? || !File.file?(abs_path)
        return nil unless Jekyll::Utils.has_yaml_header?(abs_path)

        opts = site.respond_to?(:file_read_opts) ? site.file_read_opts : {}
        content = File.read(abs_path, **opts)
        return nil unless content =~ Jekyll::Document::YAML_FRONT_MATTER_REGEXP

        data = SafeYAML.load(Regexp.last_match(1))
        data.is_a?(Hash) ? data : nil
      rescue StandardError
        nil
      end

      # Posts need a dated filename: front matter date -> modified_date -> mtime.
      def date_prefix(abs_path, name, site, data = nil)
        return nil if name.match?(Jekyll::Document::DATE_FILENAME_MATCHER)

        data = front_matter(abs_path, site) if data.nil? && abs_path
        date = date_from_front_matter(data) || File.mtime(abs_path)
        date.strftime("%Y-%m-%d")
      rescue StandardError => e
        Jekyll.logger.warn "Authors:", "Failed to read the date of #{abs_path}: #{e.message}"
        nil
      end

      def date_from_front_matter(data)
        return nil unless data.is_a?(Hash)

        value = data["date"]
        value = data["modified_date"] if value.nil? || value.to_s.strip.empty?
        return nil if value.nil? || value.to_s.strip.empty?

        Jekyll::Utils.parse_date(value.to_s, "Authors: cannot parse date #{value}")
      rescue StandardError
        nil
      end

      def manifest_path(site)
        site.in_cache_dir(MANIFEST_NAME)
      end

      # Accepts the legacy array manifest and the current
      # { "version": 2, "files": { rel => sha256 } } format.
      def read_manifest(site)
        path = manifest_path(site)
        return {} unless File.file?(path)

        data = JSON.parse(File.read(path, :encoding => "UTF-8"))
        case data
        when Hash
          files = data["files"]
          return {} unless files.is_a?(Hash)

          files.each_with_object({}) do |(rel, digest), hash|
            hash[normalize_rel(rel.to_s)] = digest.to_s.empty? ? nil : digest.to_s
          end
        when Array
          data.each_with_object({}) { |entry, hash| hash[normalize_rel(entry.to_s)] = nil }
        else
          {}
        end
      rescue StandardError
        {}
      end

      def write_manifest(site, owned)
        path = manifest_path(site)
        FileUtils.mkdir_p(File.dirname(path))
        payload = { "version" => 2, "files" => owned }
        File.write(path, JSON.pretty_generate(payload), :encoding => "UTF-8")
      rescue StandardError => e
        Jekyll.logger.warn "Authors:", "Failed to write the mirror manifest: #{e.message}"
      end

      def track(site, owned, cfg)
        @states ||= {}
        @states[site.object_id] = {
          :site     => site,
          :owned    => owned,
          :manifest => manifest_path(site),
          :keep     => cfg["keep_mirror"] ? true : false,
        }
      end

      def log_report(report)
        missing = (report[:missing] || {}).keys.sort
        unless missing.empty?
          shown = missing.first(3).join(", ")
          more = missing.size > 3 ? " and #{missing.size - 3} more" : ""
          Jekyll.logger.warn "Authors:",
                             "Category page missing (create <category>.md, or set " \
                             "category_page: true on an author file): " \
                             "#{shown}#{more}; related copies were skipped"
        end

        invalid = (report[:invalid] || {}).keys.sort
        unless invalid.empty?
          Jekyll.logger.warn "Authors:", "Invalid category value, skipped: #{invalid.first(3).join(', ')}"
        end

        if report[:string_categories]
          Jekyll.logger.debug "Authors:",
                              "categories is a string; it is split on whitespace (pages that are " \
                              "not mapped stay one group in CategoryOrder)"
        end

        fallback = report[:fallback].to_i
        unless fallback.zero?
          Jekyll.logger.warn "Authors:",
                             "#{fallback} page(s) fell back to authors/<author>/... " \
                             "(no usable category or empty title)"
        end

        log_category_page_report(report)
      end

      # Warnings for the `category_page: true` switch.
      def log_category_page_report(report)
        top_level = (report[:cp_top_level] || {}).keys.sort
        unless top_level.empty?
          Jekyll.logger.warn "Authors:",
                             "Top level category pages are created by the site owner, not by " \
                             "authors; category_page: true ignored for: " \
                             "#{top_level.first(3).join(', ')}"
        end

        owner = (report[:cp_owner] || {})
        unless owner.empty?
          shown = owner.first(3).map { |id, rel| "#{id} (#{rel})" }.join(", ")
          Jekyll.logger.warn "Authors:",
                             "Category page is maintained by the site owner, author copy " \
                             "falls back to authors/<author>/...: #{shown}"
        end

        duplicate = (report[:cp_duplicate] || {})
        unless duplicate.empty?
          shown = duplicate.first(3).map { |id, author| "#{id} (kept #{author})" }.join(", ")
          Jekyll.logger.warn "Authors:",
                             "Another author already provides this category page: #{shown}"
        end

        no_id = (report[:cp_no_id] || {}).keys.sort
        unless no_id.empty?
          Jekyll.logger.warn "Authors:",
                             "category_page: true without a category and without a folder path " \
                             "to take one from: #{no_id.first(3).join(', ')}"
        end

        invalid = (report[:cp_invalid] || {}).keys.sort
        unless invalid.empty?
          Jekyll.logger.warn "Authors:",
                             "Invalid category for category_page: true, skipped: " \
                             "#{invalid.first(3).join(', ')}"
        end

        special = (report[:cp_special] || {}).keys.sort
        unless special.empty?
          Jekyll.logger.warn "Authors:",
                             "category_page: true does not apply inside _posts/ or _drafts/: " \
                             "#{special.first(3).join(', ')}"
        end

        multi = (report[:cp_multi] || {}).keys.sort
        unless multi.empty?
          Jekyll.logger.warn "Authors:",
                             "A category page should declare one category; using the deepest: " \
                             "#{multi.first(3).join(', ')}"
        end

        shadowed = (report[:shadowed] || {}).keys.sort
        unless shadowed.empty?
          Jekyll.logger.warn "Authors:",
                             "Copies skipped because the target is a category page: " \
                             "#{shadowed.first(3).join(', ')}"
        end
      end

      # Remove directories that became empty, bottom up (never above the site root).
      def prune_dirs(site, rels)
        root = normalize_rel(site.source).chomp("/")
        dirs = rels.map { |rel| File.dirname(site.in_source_dir(rel)) }
                   .map { |dir| normalize_rel(dir) }
                   .uniq
        dirs.sort_by { |dir| -dir.length }.each do |dir|
          dir = dir.chomp("/")
          while dir.length > root.length && dir.start_with?("#{root}/") &&
                File.directory?(dir) && Dir.empty?(dir)
            Dir.rmdir(dir)
            parent = normalize_rel(File.dirname(dir))
            break if parent == dir

            dir = parent
          end
        end
      rescue StandardError
        nil
      end

      # Fallback author lookup based on the mirrored path.
      def author_from_path(key)
        segments = key.split("/")
        return nil if segments.empty?

        case segments[0]
        when POST_DIR, DRAFT_DIR
          segments[1]
        when @page_dir.to_s
          return nil if segments.size < 2

          File.basename(segments[1], File.extname(segments[1]))
        else
          segments[0].to_s.start_with?("_") && segments[1] ? segments[1] : nil
        end
      end

      def warn_unsafe_author(author)
        pattern = Jekyll::Tags::IncludeTag::VALID_FILENAME_CHARS
        return if author.match?(pattern)

        Jekyll.logger.warn "Authors:",
                           "Author folder #{author.inspect} contains characters that are unsafe " \
                           "for include paths; include_author may not work - prefer an ASCII slug"
      end

      def relative_to(base, path)
        base = normalize_rel(base).chomp("/")
        full = normalize_rel(path)
        return nil unless full.start_with?("#{base}/")

        full[(base.length + 1)..]
      end

      def normalize_rel(value)
        value.to_s.tr("\\", "/").sub(%r!\A\./!, "").sub(%r!\A/+!, "")
      end

      def posix_join(*parts)
        parts.compact.map(&:to_s).reject { |part| part.empty? || part == "." }
             .join("/").gsub(%r{/+}, "/")
      end
    end
  end
end

module Jekyll
  module Tags
    # {% include_author note.html %}
    #
    # Looks the file up in the current document's author folder
    # (_includes/<author>/) first and falls back to the global _includes/.
    # The author is resolved from the mapping table that Authors.rb builds for
    # every mirrored file; outside author content the tag behaves like a normal
    # include.
    class IncludeAuthorTag < IncludeTag
      def tag_includes_dirs(context)
        site = context.registers[:site]
        author = Jekyll::Authors.author_for(context.registers[:page])
        dirs = []
        dirs << site.in_source_dir(Jekyll::Authors::INCLUDE_DIR, author) if author
        dirs.concat(Array(super))
      end
    end
  end
end

Liquid::Template.register_tag("include_author", Jekyll::Tags::IncludeAuthorTag)

Jekyll::Hooks.register :site, :after_reset do |site|
  Jekyll::Authors.mirror(site)
end

Jekyll::Hooks.register :site, :post_read do |site|
  Jekyll::Authors.narrow_category_groups(site)
end

at_exit do
  Jekyll::Authors.cleanup_all
end
