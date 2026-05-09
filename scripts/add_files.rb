#!/usr/bin/env ruby
# Usage: ruby scripts/add_files.rb <target_name> <source_root> file1.swift file2.swift ...
# Example: ruby scripts/add_files.rb LuminaVaultClient LuminaVaultClient/LuminaVaultClient \
#            API/Core/HTTPMethod.swift API/Core/APIError.swift
#
# Adds Swift source files to the given target in LuminaVaultClient.xcodeproj.
# Files are assumed to be relative to <source_root>.
# Groups are created automatically matching the directory structure.

require 'xcodeproj'

PROJECT_PATH = File.join(__dir__, '..', 'LuminaVaultClient.xcodeproj')
TARGET_NAME  = ARGV.shift
SOURCE_ROOT  = ARGV.shift  # e.g. "LuminaVaultClient/LuminaVaultClient"
FILES        = ARGV        # remaining args are file paths relative to SOURCE_ROOT

if TARGET_NAME.nil? || SOURCE_ROOT.nil? || FILES.empty?
  puts "Usage: ruby scripts/add_files.rb <target_name> <source_root> file1.swift ..."
  exit 1
end

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }

unless target
  puts "ERROR: Target '#{TARGET_NAME}' not found. Available: #{project.targets.map(&:name).join(', ')}"
  exit 1
end

# Find or create the root source group (matches the source root folder name)
root_group_name = File.basename(SOURCE_ROOT)
root_group = project.main_group.children.find { |g| g.display_name == root_group_name }
unless root_group
  root_group = project.main_group.new_group(root_group_name, root_group_name)
end

def find_or_create_group(parent_group, path_components, base_path)
  return parent_group if path_components.empty?
  component = path_components.first
  group = parent_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.display_name == component }
  unless group
    # path is relative to project root
    dir_path = File.join(base_path, component)
    group = parent_group.new_group(component, dir_path)
  end
  find_or_create_group(group, path_components[1..], File.join(base_path, component))
end

added = []
skipped = []

FILES.each do |relative_path|
  full_disk_path = File.join(File.dirname(PROJECT_PATH), SOURCE_ROOT, relative_path)
  unless File.exist?(full_disk_path)
    puts "  SKIP (not on disk): #{relative_path}"
    skipped << relative_path
    next
  end

  # Check if already in project
  already = project.files.any? { |f| f.real_path.to_s == File.expand_path(full_disk_path) }
  if already
    puts "  SKIP (already in project): #{relative_path}"
    skipped << relative_path
    next
  end

  dir_parts  = File.dirname(relative_path).split('/').reject { |p| p == '.' }
  file_name  = File.basename(relative_path)
  group      = find_or_create_group(root_group, dir_parts, File.join(root_group_name, *dir_parts.take(0)))

  file_ref   = group.new_file(full_disk_path)
  target.add_file_references([file_ref])
  added << relative_path
  puts "  ADDED: #{relative_path}"
end

project.save

puts "\nDone. Added #{added.size}, skipped #{skipped.size}."
