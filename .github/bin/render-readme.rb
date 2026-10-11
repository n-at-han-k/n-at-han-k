#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders README.md from .github/repos.yml.
#
#   render-readme.rb           write README.md
#   render-readme.rb --check   exit 1 if README.md is not what repos.yml says
#                              it should be, and print the diff
#
# The registry is also what the converge workflow reads, so a malformed entry
# here breaks more than the profile page. Everything is validated up front and
# the script exits non-zero with the reason rather than writing half a file.

require "yaml"

ROOT = File.expand_path("../..", __dir__)
REGISTRY = File.join(ROOT, ".github", "repos.yml")
README = File.join(ROOT, "README.md")

GENERATED_BY = ".github/repos.yml"

def die(message)
  warn "render-readme: #{message}"
  exit 1
end

def load_registry
  data = YAML.safe_load_file(REGISTRY)
  die "#{REGISTRY} is not a mapping" unless data.is_a?(Hash)

  %w[title tagline sections].each do |key|
    die "missing top-level key `#{key}`" unless data.key?(key)
  end
  die "`sections` is not a list" unless data["sections"].is_a?(Array)
  die "`sections` is empty" if data["sections"].empty?

  seen = {}
  data["sections"].each_with_index do |section, i|
    die "section #{i} is not a mapping" unless section.is_a?(Hash)
    title = section["title"]
    die "section #{i} has no `title`" if title.nil? || title.to_s.strip.empty?

    converge = section["converge"]
    unless converge.nil? || converge == "kettle-jem"
      die "section #{title.inspect}: unknown `converge` value #{converge.inspect} " \
          "(only `kettle-jem` is understood)"
    end

    repos = section["repos"]
    die "section #{title.inspect} has no `repos`" unless repos.is_a?(Array)
    die "section #{title.inspect} has an empty `repos`" if repos.empty?

    repos.each_with_index do |entry, j|
      die "section #{title.inspect} repo #{j} is not a mapping" unless entry.is_a?(Hash)
      slug = entry["repo"]
      die "section #{title.inspect} repo #{j} has no `repo`" if slug.nil?
      unless slug.to_s.match?(%r{\A[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\z})
        die "#{slug.inspect} is not an `owner/name` slug"
      end
      if seen.key?(slug)
        die "#{slug} is listed twice (#{seen[slug].inspect} and #{title.inspect})"
      end
      seen[slug] = title

      unknown = entry.keys - %w[repo description converge]
      die "#{slug}: unknown key(s) #{unknown.join(", ")}" unless unknown.empty?

      # Only `false` is meaningful per repo: a repo cannot opt *into* a
      # template its section does not name, and silently accepting
      # `converge: kettle-jem` here would imply it could.
      if entry.key?("converge") && entry["converge"] != false
        die "#{slug}: per-repo `converge` may only be `false`, got #{entry["converge"].inspect}"
      end
      if entry["converge"] == false && converge.nil?
        die "#{slug}: `converge: false` is redundant — section #{title.inspect} converges nothing"
      end
    end
  end

  data
end

def render(data)
  out = +"## #{data["title"]}\n\n#{data["tagline"]}\n"

  data["sections"].each do |section|
    out << "\n## #{section["title"]}\n"
    section["repos"].each do |entry|
      slug = entry["repo"]
      name = slug.split("/").last
      line = "- [#{name}](https://github.com/#{slug})"
      description = entry["description"]
      line << " - #{description}" unless description.nil? || description.to_s.strip.empty?
      out << line << "\n"
    end
  end

  out
end

registry = load_registry
rendered = render(registry)

if ARGV.include?("--check")
  current = File.exist?(README) ? File.read(README) : ""
  if current == rendered
    puts "README.md is up to date with #{GENERATED_BY}"
    exit 0
  end

  warn "README.md is out of date with #{GENERATED_BY}. Run:"
  warn "    ruby .github/bin/render-readme.rb"
  require "tempfile"
  Tempfile.create("README.expected") do |f|
    f.write(rendered)
    f.flush
    system("diff", "-u", "--label", "README.md", "--label", "expected", README, f.path)
  end
  exit 1
end

File.write(README, rendered)
puts "wrote README.md from #{GENERATED_BY} " \
     "(#{registry["sections"].sum { |s| s["repos"].length }} repos in #{registry["sections"].length} sections)"
