class PagesController < ApplicationController
  include PagesHelper
  require 'media_wiki'
  before_filter :check_uri
  respond_to :json, :html

  def check_uri
    title = params[:title]
    if title == nil
      return
    end
    if title.include?(" ")
      title = title.tr!(" ", "_")
      redirect_to "/wiki/#{title}"
    end
  end

  def delete
    logger.debug(current_user.role)
    if current_user and (current_user.role=="admin")
      title = params[:id]
      page = Page.new.create(title)
      page.delete
    end
    render :json => {:success => true}
  end

  def show
    @title = params[:title]
    if @title == nil
      @title = "101companies:Project"
    end
    @page = Page.new.create @title

    @page.instance_eval { class << self; self end }.send(:attr_accessor, "history")
    if not History.where(:page => @title).exists?
      @page.history = History.create!(
        user: current_user,
        page: @title,
        version: 1
      )
    else
     @page.history = History.where(:page => @title).first
    end

    respond_with @page
  end

  def parse
    content = params[:content]
    #we use the title to get the context of the page
    title = params[:pagetitle]
    wiki = WikiCloth::Parser.new(:data => content, :noedit => true)
    page = Page.new.create title
    WikiParser.context = page.context

    html = wiki.to_html
    wiki.internal_links.each do |link|
      html.gsub!("<a href=\"#{link}\"", "<a href=\"/wiki/#{link}\"")
    end
    render :json => {:success => true, :html => html.html_safe}
  end

  def search
    @query_string = params[:q]
    if @query_string == ''
      redirect_to "/wiki/"
    else
      gw = MediaWiki::Gateway.new('http://mediawiki.101companies.org/api.php')
      gw.login(ENV['WIKIUSER'], ENV['WIKIPASSWORD'])
      @search_results = gw.search(@query_string)
      respond_with @search_results
    end
  end

  def summary
    begin
      GC.disable
      title = params[:id]
      page = Page.new.create(title)
      render :json => {:sections => page.sections, :internal_links => page.internal_links}
    rescue
      @error_message="#{$!}"
      render :json => {:success => false, :error => @error_message}
    ensure
      GC.enable
      GC.start
    end
  end

  # get all sections for a page
  def sections
    begin
      title = params[:id]
      page = Page.new.create(title)
      sections = page.sections
      respond_with sections
    rescue
      @error_message="#{$!}"
      render :json => {:success => false, :error => @error_message}
    end
  end


  # get all internal links for the page
  def internal_links
    begin
      title = params[:id]
      page = Page.new.create(title)
      respond_with page.internal_links
    rescue
      @error_message="#{$!}"
      render :json => {:success => false, :error => @error_message}
    end
  end

  def update
    # check if operation is not permitted
    if cannot? :update, self
      render :json => {:success => false} and return
    end
    title = params[:title]
    sections = params[:sections]
    page = Page.new.create(title)
    if params.has_key?('content') and params[:content] != ""
      page.change(params[:content])
    else
      content = ""
      sections.each { |s| content += s['content'] + "\n" }
      page.change(content)
    end

    if History.where(:page => title).exists?
      history = History.where(:page => title).first
      history.update_attributes(
        version: history.version + 1,
        user: current_user
      )
    else
      History.create!(
        page: title,
        version: 1,
        user: current_user
      )
    end

    render :json => {:success => true}
  end

  def section
    title = params[:id]
    p = Page.new.create(title)
    section = {'content' => p.section(params[:title])}
    respond_with section.to_json
  end

  private
    def gateway
      if @_gateway == nil
        @_gateway = MediaWiki::Gateway.new('http://mediawiki.101companies.org/api.php')
      else
        return @_gateway
      end
    end
end
