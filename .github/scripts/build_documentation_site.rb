# frozen_string_literal: true

require 'cgi'
require 'fileutils'

site, version = ARGV
abort 'Usage: build_documentation_site.rb OUTPUT_DIRECTORY VERSION' unless site && version

%w[swift/documentation/kaiwakit/index.html android/index.html].each do |page|
  abort "Missing generated API documentation: #{page}" unless File.file?(File.join(site, page))
end

root = File.expand_path('../..', __dir__)
template = File.read(File.join(root, 'docs/site/index.html'))
# Used in HTML text, attributes and installation snippets. Restrict to a release
# tag so path separators and query characters cannot alter download links.
abort 'Invalid documentation version' unless version.match?(/\A[\w.\-]+\z/)
FileUtils.mkdir_p(File.join(site, 'assets'))
FileUtils.cp(File.join(root, 'docs/site/site.css'), File.join(site, 'assets/site.css'))
FileUtils.cp(File.join(root, 'docs/images/macos-sample.png'), File.join(site, 'assets/macos-sample.png'))
File.write(File.join(site, '.nojekyll'), '')
File.write(File.join(site, 'index.html'), template.gsub('{{VERSION}}', CGI.escapeHTML(version)))
