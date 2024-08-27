#!/usr/bin/env ruby

require "net/http"
require "json"
require "open-uri"
require "digest"
require "fileutils"
require "uri"
require "optparse"

class PuppetForgeMirror
  def initialize(forge_url, modules_dir, max_size)
    @modules_dir = modules_dir
    @forge_url = forge_url
    @max_size = max_size
  end

  def http_get(url)
    uri = URI(url)

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", options: { open_timeout: 300 }) do |http|
      request = Net::HTTP::Get.new uri
      response = http.request request

      if response.code != "200"
        puts "Error #{response.code}: Failed to get #{uri}"
        return nil
      end
      response.body
    end
  end

  def download_module(url, mod, owner, filename, checksum)
    module_dir = File.join(@modules_dir, owner, mod)
    filepath = File.join(module_dir, filename)

    FileUtils.mkdir_p module_dir unless File.exist? module_dir

    if File.exist? filepath
      return if Digest::MD5.file(filepath).hexdigest == checksum
    end

    puts "downloading #{url}"
    data = http_get(url)
    return if data.nil?
    open(filepath, "wb") { |f| f.write(data) }
  end

  def download_modules
    url = URI.join(@forge_url, "/v3/releases")
    while data = http_get(url)
      break if data.nil?

      r = JSON.parse(data)
      r["results"].each do |m|
        if m["file_size"] > 1024 * 1024 * @max_size.to_i
          puts "#{m["metadata"]["name"]} is too big, skipping"
          next
        end
        download_module(
          URI.join(@forge_url, m["file_uri"]),
          m["module"]["name"],
          m["module"]["owner"]["username"],
          m["file_uri"].split("/").last,
          m["file_md5"]
        )
      end
      next_url = r["pagination"]["next"]
      break if next_url.nil?
      url = URI.join(@forge_url, next_url)
    end
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: puppet-forge-mirror [options]"
  opts.on("-m", "--modulepath PATH", "Downloaded modules will be stored here") do |path|
    options[:modulepath] = path
  end
  opts.on("--max-size MB", "Maximum size of module in megabyte, bigger modules will be skipped") do |max_size|
    options[:max_size] = max_size
  end
end.parse!

if options[:modulepath].nil?
  puts "No modulepath specified"
  exit 1
end

options[:max_size] = 20 if options[:max_size].nil?

fm = PuppetForgeMirror.new("https://forgeapi.puppetlabs.com", options[:modulepath], options[:max_size])
fm.download_modules
