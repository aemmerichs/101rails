require 'media_wiki'

class Page

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  search_in :title, :namespace, :page_title_namespace, :raw_content

  field :title, type: String
  # namespace for page, need to be set
  field :namespace, type: String
  field :page_title_namespace, type: String
  field :raw_content, type: String, :default => ""
  field :html_content, type: String
  field :used_links, type: Array
  field :subresources, type: Array

  field :worker_findings, type: String

  # relations here
  has_one :repo_link
  has_many :page_changes
  has_many :matching_service_requests
  has_and_belongs_to_many :users, :class_name => 'User', :inverse_of => :pages

  validates_uniqueness_of :page_title_namespace
  validates_presence_of :title
  validates_presence_of :namespace

  attr_accessible :user_ids, :raw_content, :namespace, :title, :repo_link_id, :worker_findings

  before_validation do
    preparing_the_page
  end

  def preparing_the_page
    # prepare field namespace + title
    self.page_title_namespace = self.namespace.to_s + ':' + self.title.to_s
    # TODO: restore later
    #self.inject_namespace_triple
    # fill used_links with links in page
    # parse content and get internal links
    wiki_parser = self.create_wiki_parser
    begin
      # this produces internal_links
      wiki_parser.to_html
      # TODO: combine with line above later
      self.html_content = self.parse
    rescue
      Rails.logger.info "Failed producing html for page #{self.full_title}"
    end
    # if exist internal_links -> fill used_links
    # if wiki_parser.internal_links
    #  self.used_links = wiki_parser.internal_links.map { |link| PageModule.unescape_wiki_url link }
    #end

    self.subresources = []
    self.used_links   = []
    # these are the links which are used in sections annotated as subresources of the page
    wiki_parser.section_list.each do |s|
      p = WikiCloth::Parser.new(:data => s.wikitext, :noedit => true)
      p.to_html
      l = p.internal_links.map { |link| PageModule.unescape_wiki_url link }
      if s.is_resource_section
        self.subresources << {s.title => l}
      else
        self.used_links << l
      end
    end
    self.used_links.flatten!
  end

  def get_metadata_section(sections)
    sections.select { |section| section["title"] == 'Metadata' }
  end

  def inject_namespace_triple
    self.inject_triple "instanceOf::Namespace:#{self.namespace}"
  end

  def inject_triple(namespace_triple)
    sections = self.sections
    # find metadata section
    metadata_section = get_metadata_section sections
    # not found -> create it
    if metadata_section.empty?
      if self.raw_content.nil?
        self.raw_content = ""
      end
      self.raw_content = self.raw_content + "\n== Metadata =="
      wiki_parser = self.create_wiki_parser self.raw_content
      sections = self.sections wiki_parser
    end
    metadata_section = get_metadata_section(sections)[0]
    unless metadata_section
      Rails.logger.info "In page #{self.full_title} cannot be any triple injected."
      return
    end
    unless metadata_section["content"].include? namespace_triple
      metadata_section["content"] = metadata_section["content"] + "\n<!-- Next link is generated automatically-->"
      metadata_section["content"] = metadata_section["content"] + "\n* [[#{namespace_triple}]]"
    end
    # rebuild content from sections
    self.raw_content = build_content_from_sections sections
  end

  def decorate_headline(headline_text)
    # if string is too long -> cut to 250 chars and add '...' at the end
    popup_msg_length = 250
    (headline_text.length < popup_msg_length)  ? headline_text : "#{headline_text[0..popup_msg_length-1]} ..."
  end

  def get_last_change
    last_change = self.page_changes.last
    if last_change and last_change.user
      history_entry = {
          user_name: last_change.user.name,
          user_pic: last_change.user.github_avatar,
          user_email: last_change.user.email,
          created_at: last_change.created_at
      }
    else
      history_entry = {}
    end
    history_entry
  end

  def get_headline
    # assume that first <p> in html content will be shown as popup
    headline_elem = Nokogiri::HTML(self.html_content).css('p').first
    headline_elem.nil? ?
        "No headline found for page #{self.full_title}" : (decorate_headline(headline_elem.text)).strip
  end

  def create_track(user)
    PageChange.new :page => self,
                   :raw_content => self.raw_content,
                   :title => self.title,
                   :namespace => self.namespace,
                   :user => user
  end

  def parse(content = self.raw_content)
    parsed_page = self.create_wiki_parser content
    parsed_page.sections.first.auto_toc = false
    html = parsed_page.to_html
    # mark empty or non-existing page with class missing-link (red color)
    parsed_page.internal_links.each do |link|
      nice_link = PageModule.url link
      used_page = PageModule.find_by_full_title nice_link
      # if not found page or it has no content
      # set in class_attribute additional class for link (mark with red)
      class_attribute = (used_page.nil? || used_page.raw_content.nil? || used_page.raw_content.strip == "") ?
          'class="missing-link"' : ''
      # replace page links in html
      used_page ? popup = used_page.get_headline : popup = ""
      html.gsub! "<a href=\"#{link}\"", "<a #{class_attribute}"+
          "data-original-title=\"#{popup}\" href=\"/wiki/#{nice_link}\""
    end
    return html.html_safe
  end

  # get fullname with namespace and  title
  def full_title
    # if used default namespaces -> remove from full title
    if (self.namespace == '101') or (self.namespace == 'Concept')
      return self.title
    end
    # else use normal building of full url
    self.namespace + ':' + self.title
  end

  def rewrite_backlink(backlink, old_title)
    # find page by backlink
    related_page = PageModule.find_by_full_title backlink
    if !related_page.nil?
      # rewrite link in page, found by backlink
      related_page.raw_content = related_page.rewrite_internal_links old_title, self.full_title
      # and save changes
      if !related_page.save
        Rails.logger.info "Failed to rewrite links for page " + related_page.full_title
      end
    else
      Rails.logger.info "Couldn't find page with link " + backlink
    end
  end

  def rename(new_title)
    # set new title to page
    nt = PageModule.retrieve_namespace_and_title new_title
    old_title = self.full_title
    # save old backlinsk before renaming
    old_backlinks = self.backlinks
    # rename the page
    self.namespace = nt['namespace']
    self.title = nt['title']
    # rewrite links in pages, that links to the page
    old_backlinks.each { |old_backlink| self.rewrite_backlink old_backlink, old_title }
  end

  def build_content_from_sections(sections)
    content = ""
    sections.each { |s| content += s['content'] + "\n" }
    content
  end

  def update_or_rename(new_title, content, sections)
    # if content is empty -> populate content with sections
    if content == ""
      content = build_content_from_sections(sections)
    end
    self.raw_content = content
    # unescape new title to nice readable url
    new_title = PageModule.unescape_wiki_url new_title
    # if title was changed -> rename page
    if (new_title!=self.full_title and PageModule.find_by_full_title(new_title).nil?)
      self.rename(new_title)
    end
    self.save
  end

  # TODO: black magic
  def rewrite_internal_links(from, to)
    regex = /(\[\[:?)([^:\]\[]+::)?(#{Regexp.escape(from.gsub("_", " "))})(\s*)(\|[^\[\]]*)?(\]\])/i
    self.raw_content.gsub("_", " ").gsub(regex) do
      "#{$1}#{$2}#{$3[0].downcase == $3[0] ? PageModule.uncapitalize_first_char(to) : to}#{$4}#{$5}#{$6}"
    end
  end

  def url
    PageModule.url self.full_title
  end

  def create_wiki_parser(content=nil)
    WikiCloth::Parser.context = {:ns => (MediaWiki::send :upcase_first_char, self.namespace), :title => self.title}
    WikiCloth::Parser.new(:data => ((content.nil?) ? self.raw_content : content), :noedit => true)
  end

  def semantic_links
    self.used_links.select {|link| link.include? "::" }
  end

  def internal_links
    self.used_links
  end

  def sections(wiki_parser = self.create_wiki_parser)
    sections = []
    self.create_wiki_parser.sections.first.children.each do |section|
      content_with_subsections = section.wikitext.sub(/\s+\Z/, "")
      begin
        parsed_html = parse content_with_subsections
      rescue
        parsed_html = "This section wan't properly rendered =/"
      end
      sections << {
          'is_resource' => section.is_resource_section,
          'title' => section.title,
          'content' => content_with_subsections,
          'html_content' => parsed_html
      }
    end
    sections
  end

  def backlinks
    weak_backlinks = Page.where(:used_links => /^~#{self.full_title}$/i)
    strong_backlinks = Page.where(:used_links => /^#{self.full_title}$/i)
    (weak_backlinks + strong_backlinks).map { |page| page.full_title}
  end

  def section(section)
    self.create_wiki_parser.sections.first.children.find { |s| s.full_title.downcase == section.downcase }
  end

end
