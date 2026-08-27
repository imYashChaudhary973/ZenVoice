#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a Sparkle appcast.xml for a ZenVoice release.
#
# Usage:
#   ./Scripts/generate-appcast.rb \
#     --version 0.4.2 \
#     --dmg build/ZenVoice.dmg \
#     --feed-url https://example.com/zenvoice/appcast.xml \
#     --private-key /secure/path/to/Sparkle-private-key.pem \
#     --output build/appcast.xml
#
# The script computes the DMG SHA-256, file size, and Sparkle Ed25519 signature
# using Sparkle's sign_update tool, then emits a valid appcast.xml with one
# <item> for the release. Release notes for the requested version are pulled
# from CHANGELOG.md.
#
# Security: the private key path is read from the command line and used only by
# sign_update. Never commit a real private key to the repository.

require 'digest'
require 'fileutils'
require 'optparse'
require 'rexml/document'

options = {
  version: nil,
  dmg: nil,
  feed_url: nil,
  private_key: nil,
  output: 'appcast.xml'
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} --version VERSION --dmg PATH --feed-url URL --private-key PATH [--output PATH]"
  opts.on('--version VERSION', 'Release version (e.g. 0.4.2)') { |v| options[:version] = v }
  opts.on('--dmg PATH', 'Path to the release DMG') { |p| options[:dmg] = p }
  opts.on('--feed-url URL', 'Public URL where appcast.xml will be hosted') { |u| options[:feed_url] = u }
  opts.on('--private-key PATH', 'Path to the Sparkle Ed25519 private key file') { |p| options[:private_key] = p }
  opts.on('--output PATH', 'Output appcast.xml path') { |p| options[:output] = p }
end.parse!

%i[version dmg feed_url private_key].each do |required|
  raise OptionParser::MissingArgument, "--#{required.to_s.tr('_', '-')}" if options[required].nil?
end

project_dir = File.expand_path('..', __dir__)
dmg_path = File.expand_path(options[:dmg])
key_path = File.expand_path(options[:private_key])
output_path = File.expand_path(options[:output])

raise "DMG not found: #{dmg_path}" unless File.exist?(dmg_path)
raise "Private key not found: #{key_path}" unless File.exist?(key_path)

length = File.size(dmg_path)
sha256 = Digest::SHA256.file(dmg_path).hexdigest

# Locate Sparkle's sign_update tool. Prefer a local copy if the project vendors
# Sparkle binaries, otherwise rely on PATH.
sparkle_bin_dir = File.join(project_dir, 'vendor', 'sparkle', 'bin')
sign_update = File.join(sparkle_bin_dir, 'sign_update')
sign_update = 'sign_update' unless File.executable?(sign_update)

signature = nil
IO.popen([sign_update, '--private-key-file', key_path, dmg_path], err: [:child, :out]) do |io|
  signature = io.read.strip
end
raise "sign_update failed or produced no output" if signature.nil? || signature.empty?

# Pull release notes for this version from CHANGELOG.md.
changelog_path = File.join(project_dir, 'CHANGELOG.md')
raise "CHANGELOG.md not found" unless File.exist?(changelog_path)

notes_lines = []
collecting = false
File.foreach(changelog_path, chomp: true) do |line|
  if line =~ /^##\s+\[#{Regexp.escape(options[:version])}\]/
    collecting = true
    next
  elsif collecting && line =~ /^##\s+\[/
    break
  end
  notes_lines << line if collecting
end

# Trim leading and trailing blank lines, then fall back to a short default.
notes_lines.shift while notes_lines.first && notes_lines.first.strip.empty?
notes_lines.pop while notes_lines.last && notes_lines.last.strip.empty?
release_notes = notes_lines.empty? ? "ZenVoice #{options[:version]} release." : notes_lines.join("\n")

# Build the appcast XML with REXML to avoid hand-escaped attributes.
doc = REXML::Document.new
rss = REXML::Element.new('rss')
rss.add_attributes({
  'xmlns:sparkle' => 'http://www.andymatuschak.org/xml-namespaces/sparkle',
  'version' => '2.0'
})
doc << rss

channel = REXML::Element.new('channel')
rss << channel

channel << REXML::Element.new('title').tap { |e| e.text = 'ZenVoice' }
channel << REXML::Element.new('link').tap { |e| e.text = options[:feed_url] }
channel << REXML::Element.new('description').tap { |e| e.text = 'ZenVoice release feed' }
channel << REXML::Element.new('language').tap { |e| e.text = 'en' }

item = REXML::Element.new('item')
channel << item

item << REXML::Element.new('title').tap { |e| e.text = "ZenVoice #{options[:version]}" }
item << REXML::Element.new('pubDate').tap { |e| e.text = Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT') }

sparkle_version = REXML::Element.new('sparkle:version')
sparkle_version.text = options[:version]
item << sparkle_version

sparkle_short_version = REXML::Element.new('sparkle:shortVersionString')
sparkle_short_version.text = options[:version]
item << sparkle_short_version

description = REXML::Element.new('description')
description.text = REXML::CData.new(release_notes)
item << description

enclosure = REXML::Element.new('enclosure')
enclosure.add_attributes({
  'url' => "https://github.com/imYashChaudhary973/ZenVoice/releases/download/v#{options[:version]}/ZenVoice.dmg",
  'length' => length.to_s,
  'type' => 'application/octet-stream',
  'sparkle:version' => options[:version],
  'sparkle:shortVersionString' => options[:version],
  'sparkle:edSignature' => signature
})
item << enclosure

# Optional digest element for clients that prefer SHA-256 verification.
sparkle_digest = REXML::Element.new('sparkle:digest')
sparkle_digest.add_attributes({ 'algorithm' => 'sha-256' })
sparkle_digest.text = sha256
item << sparkle_digest

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, doc.to_s)

puts "Generated #{output_path}"
puts "length: #{length}"
puts "sha256: #{sha256}"
puts "signature: #{signature}"
