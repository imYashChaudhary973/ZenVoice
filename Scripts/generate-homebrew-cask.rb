#!/usr/bin/env ruby
# frozen_string_literal: true

# Stubs a Homebrew cask file for ZenVoice.
# In a real release flow this script computes the zip SHA-256 and optionally
# opens a PR against a dedicated homebrew-tap repository.
#
# Usage:
#   ./Scripts/generate-homebrew-cask.rb --version 0.3.0 --zip build/ZenVoice-distribution.zip

require 'digest'
require 'fileutils'
require 'optparse'

options = { dmg: nil, version: nil, output: nil }
OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} --version VERSION --dmg PATH [--output PATH]"
  opts.on('--version VERSION', 'Release version') { |v| options[:version] = v }
  opts.on('--dmg PATH', 'Path to distribution DMG') { |p| options[:dmg] = p }
  opts.on('--output PATH', 'Output cask file path') { |p| options[:output] = p }
end.parse!

raise OptionParser::MissingArgument, '--version' if options[:version].nil?
raise OptionParser::MissingArgument, '--dmg' if options[:dmg].nil?

dmg_path = File.expand_path(options[:dmg])
raise "DMG not found: #{dmg_path}" unless File.exist?(dmg_path)

sha256 = Digest::SHA256.file(dmg_path).hexdigest

repo_owner = ENV.fetch('ZENVOICE_HOMEBREW_TAP_OWNER', 'imYashChaudhary973')

cask = <<~CASK
  cask "zenvoice" do
    version "#{options[:version]}"
    sha256 "#{sha256}"

    url "https://github.com/#{repo_owner}/ZenVoice/releases/download/v#{options[:version]}/ZenVoice.dmg"
    name "ZenVoice"
    desc "Privacy-first macOS speech capture, transcription, and lecture summaries"
    homepage "https://github.com/#{repo_owner}/ZenVoice"

    auto_updates true

    app "ZenVoice.app"

    zap trash: [
      "~/Library/Application Support/ZenVoice",
      "~/Library/Caches/ZenVoice",
      "~/Library/Preferences/com.zenvoice.app.plist",
    ]
  end
CASK

output_path = options[:output] ? File.expand_path(options[:output]) : "Casks/zenvoice.rb"
FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, cask)

puts "Generated #{output_path}"
puts "sha256: #{sha256}"
