# A program that requires none of the libraries of the value types, and uses
# two of their names for a module and an alias of its own, which logbuch
# leaves alone. It still builds, and the types stay undefined.
require "../../../src/logbuch"

module Complex
end

struct Release
end

alias SemanticVersion = Release

puts "UUID defined: #{{{ @top_level.has_constant?("UUID") }}}"
puts "URI defined: #{{{ @top_level.has_constant?("URI") }}}"
puts "path: #{Logbuch.convert(Path["/srv"], detail: :id).as_s}"
puts "alias: #{Logbuch.convert(SemanticVersion.new, detail: :id).as_s}"
