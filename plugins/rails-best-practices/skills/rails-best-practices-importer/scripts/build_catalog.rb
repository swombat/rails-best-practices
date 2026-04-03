#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "set"

def load_catalog(skill_dir)
  catalog_path = skill_dir.join("references", "practice-catalog.json")
  JSON.parse(catalog_path.read)
end

def verify_ids!(catalog)
  practice_ids = catalog.fetch("practices").keys.to_set
  family_ids = catalog.fetch("families").map { |family| family.fetch("id") }.to_set
  bundle_ids = catalog.fetch("bundles").map { |bundle| bundle.fetch("id") }.to_set

  catalog.fetch("selection_axes").each do |axis|
    axis.fetch("choices").each do |choice|
      choice.fetch("recommended_practice_ids", []).each do |practice_id|
        raise "Unknown practice id in selection_axes: #{practice_id}" unless practice_ids.include?(practice_id)
      end

      bundle_id = choice["recommended_bundle"]
      raise "Unknown bundle id in selection_axes: #{bundle_id}" if bundle_id && !bundle_ids.include?(bundle_id)
    end
  end

  catalog.fetch("bundles").each do |bundle|
    bundle.fetch("practice_ids").each do |practice_id|
      raise "Unknown practice id in bundles: #{practice_id}" unless practice_ids.include?(practice_id)
    end
  end

  catalog.fetch("families").each do |family|
    family.fetch("practice_ids").each do |practice_id|
      raise "Unknown practice id in families: #{practice_id}" unless practice_ids.include?(practice_id)
    end

    family.fetch("overlaps", []).each do |overlap|
      overlap.fetch("practice_ids").each do |practice_id|
        raise "Unknown overlap practice id: #{practice_id}" unless practice_ids.include?(practice_id)
      end
    end
  end

  catalog.fetch("practices").each do |practice_id, practice|
    family_id = practice.fetch("family_id")
    raise "Unknown family id #{family_id} on #{practice_id}" unless family_ids.include?(family_id)

    practice.fetch("conflicts_with", []).each do |related_id|
      raise "Unknown related practice id #{related_id} on #{practice_id}" unless practice_ids.include?(related_id)
    end

    practice.fetch("complements", []).each do |related_id|
      raise "Unknown related practice id #{related_id} on #{practice_id}" unless practice_ids.include?(related_id)
    end
  end
end

def verify_paths!(catalog, skill_dir)
  catalog.fetch("practices").each do |practice_id, practice|
    doc_path = skill_dir.join(practice.fetch("doc_path"))
    raise "Missing doc for #{practice_id}: #{doc_path}" unless doc_path.exist?
  end
end

def join_values(values)
  values.join(", ")
end

def render_markdown(catalog)
  practices = catalog.fetch("practices")
  lines = []

  lines << "# Combined Rails Best Practices Menu"
  lines << ""
  lines << "Generated from `references/practice-catalog.json`."
  lines << ""
  lines << "## Starter Bundles"
  lines << ""

  catalog.fetch("bundles").each do |bundle|
    lines << "### #{bundle.fetch("label")} (`#{bundle.fetch("id")}`)"
    lines << ""
    lines << bundle.fetch("summary")
    lines << ""
    lines << "Recommended for: #{join_values(bundle.fetch("recommended_for"))}."
    lines << ""

    bundle.fetch("practice_ids").each do |practice_id|
      practice = practices.fetch(practice_id)
      lines << "- `#{practice_id}`: #{practice.fetch("title")}"
    end

    lines << ""
  end

  lines << "## Decision Axes"
  lines << ""

  catalog.fetch("selection_axes").each do |axis|
    lines << "### #{axis.fetch("question")} (`#{axis.fetch("id")}`)"
    lines << ""
    lines << axis.fetch("why_it_matters")
    lines << ""

    axis.fetch("choices").each do |choice|
      summary = "- `#{choice.fetch("id")}`: #{choice.fetch("label")}"
      practice_ids = choice.fetch("recommended_practice_ids", [])
      summary += ". Default practices: #{join_values(practice_ids)}" unless practice_ids.empty?

      bundle_id = choice["recommended_bundle"]
      summary += ". Bundle: `#{bundle_id}`" if bundle_id

      lines << summary
    end

    lines << ""
  end

  lines << "## Combined Menu"
  lines << ""

  catalog.fetch("families").each do |family|
    lines << "### #{family.fetch("label")} (`#{family.fetch("id")}`)"
    lines << ""
    lines << "Selection mode: `#{family.fetch("selection_mode")}`."
    lines << ""
    lines << family.fetch("guidance")
    lines << ""

    family.fetch("practice_ids").each do |practice_id|
      practice = practices.fetch(practice_id)
      lines << "- `#{practice_id}` (#{practice.fetch("source")}): #{practice.fetch("summary")} " \
               "Best for: #{join_values(practice.fetch("best_for"))}. " \
               "Import: #{join_values(practice.fetch("import_modes"))}. " \
               "Kind: `#{practice.fetch("kind")}`. " \
               "Doc: `#{practice.fetch("doc_path")}`"
    end

    overlaps = family.fetch("overlaps", [])
    unless overlaps.empty?
      lines << ""
      lines << "Overlap guidance:"

      overlaps.each do |overlap|
        lines << "- `#{overlap.fetch("relation")}`: #{join_values(overlap.fetch("practice_ids"))}. #{overlap.fetch("guidance")}"
      end
    end

    lines << ""
  end

  "#{lines.join("\n").rstrip}\n"
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/build_catalog.rb [--output PATH] [--stdout]"

  parser.on("--output PATH", "Output path for combined-menu.md") do |path|
    options[:output] = Pathname(path)
  end

  parser.on("--stdout", "Print the rendered menu instead of writing a file") do
    options[:stdout] = true
  end
end.parse!

script_path = Pathname(__FILE__).realpath
skill_dir = script_path.parent.parent
catalog = load_catalog(skill_dir)

verify_ids!(catalog)
verify_paths!(catalog, skill_dir)

rendered = render_markdown(catalog)
if options[:stdout]
  print(rendered)
  exit 0
end

output_path = options[:output] || skill_dir.join("references", "combined-menu.md")
output_path.write(rendered)
puts "Wrote #{output_path}"
