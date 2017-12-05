require 'json'
require 'digest'
require 'net/http'

require 'kindlerb'
require 'kindlefodder'


class WebBook < Kindlefodder

  API_KEY = ENV['MERCURY_WEB_PARSER_API_KEY']

  def document
    {
      'title' => 'Web Articles'
    }
  end

  def get_source_files
    sections = []
    ARGF.each { |url|
      sections << build_section(url)
    }

    File.open("#{output_dir}/sections.yml", 'w') { |f|
      f.puts sections.to_yaml
    }
  end

  def build_section url
    $stderr.puts "  Downloading " + url
    article = fetch_article url
    title = article['title']
    {
      title: title,
      articles: [{
        title: title,
        path: save_article_and_return_path(article)
      }]
    }
  end

  def save_article_and_return_path article
    url = article['url']
    hash = Digest::SHA256.hexdigest url
    path = "articles/#{hash}.html"
    author = article['author']
    File.open("#{output_dir}/#{path}", 'w') { |f|
      f.puts "<h1>#{article['title']}</h1>\n"
      f.puts "<h5>by #{author}</h5>\n" if author
      f.puts "<h5 style=\"text-align: right;\">#{url}</h5>\n" if url
      f.puts article['content']
    }
    return path
  end

  def fetch_article url
    uri = URI('https://mercury.postlight.com/parser')
    uri.query = URI.encode_www_form :url => url

    req = Net::HTTP::Get.new(uri)
    req['x-api-key'] = API_KEY

    res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true) { |http|
      http.request(req)
    }

    JSON.parse(res.body)
  end

  def self.make_toc_flat
    return unless File.exists?('contents.html')
    toc = File.open('contents.html') { |f| Nokogiri::XML(f) }

    links = toc.search('li')
    toc.search('h4').each &:remove
    toc.search('ul').each &:remove

    ul = Nokogiri::XML::Node.new "ul", toc
    ul.children = links
    toc.at('h1').add_next_sibling(ul)

    File.open('contents.html', 'w') { |f| f.puts toc }
  end

  def self.make_nav_flat
    return unless File.exists?('nav-contents.ncx')
    ncx = File.open('nav-contents.ncx') { |f| Nokogiri::XML(f) }

    ncx.search('navPoint.section').each { |section|
      article = section.at('navPoint')
      section.children = article.children
    }

    File.open('nav-contents.ncx', 'w') { |f| f.puts ncx }
  end

  def self.remove_section_pages
    return unless File.exists?('kindlerb.opf')
    opf = File.open('kindlerb.opf') { |f| Nokogiri::XML(f) }

    opf.search('item').each { |item| item.remove if item['id'] =~ /^item-\d{3}$/ }
    opf.search('itemref').each { |itemref| itemref.remove if itemref['idref'] =~ /^item-\d{3}$/ }
    opf.search('reference').each { |ref| ref['href'] = 'contents.html' }

    File.open('kindlerb.opf', 'w') { |f| f.puts opf }
  end

end

module Kindlerb
  class << self
    alias_method :old_executable, :executable
    def executable
      WebBook.make_toc_flat
      WebBook.make_nav_flat
      WebBook.remove_section_pages
      old_executable()
    end
  end
end

WebBook.generate

