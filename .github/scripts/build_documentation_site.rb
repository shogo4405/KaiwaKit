# frozen_string_literal: true

require 'cgi'

site, version = ARGV
abort 'Usage: build_documentation_site.rb OUTPUT_DIRECTORY VERSION' unless site && version

%w[swift/documentation/kaiwakit/index.html android/index.html].each do |page|
  abort "Missing generated API documentation: #{page}" unless File.file?(File.join(site, page))
end

version = CGI.escapeHTML(version)
File.write(File.join(site, '.nojekyll'), '')
File.write(File.join(site, 'index.html'), <<~HTML)
  <!doctype html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>KaiwaKit API Reference</title>
      <style>
        :root { color-scheme: light dark; font: 18px/1.6 system-ui, sans-serif; }
        body { max-width: 48rem; margin: 10vh auto; padding: 0 1.5rem; }
        h1 { line-height: 1.2; }
        nav { display: flex; flex-wrap: wrap; gap: 1rem; margin: 2rem 0; }
        nav a { flex: 1 1 16rem; padding: 1.5rem; border: 1px solid #888; border-radius: 12px; }
        nav strong, nav span { display: block; }
        nav span { font-size: .9rem; }
      </style>
    </head>
    <body>
      <h1>KaiwaKit API Reference</h1>
      <p>Native voice conversations with OpenAI Realtime and Gemini Live.</p>
      <p>Reference for <code>#{version}</code></p>
      <nav aria-label="API documentation">
        <a href="swift/documentation/kaiwakit/"><strong>Swift</strong><span>Apple platform SDK · DocC</span></a>
        <a href="android/index.html"><strong>Android</strong><span>Kotlin SDK · Dokka</span></a>
      </nav>
      <p><a href="https://github.com/shogo4405/KaiwaKit">Source code and examples</a></p>
    </body>
  </html>
HTML
