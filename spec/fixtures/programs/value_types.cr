# A program that requires logbuch before the libraries of the value types it
# logs, and gives two of them a `to_trace` of its own, which logbuch keeps.
require "../../../src/logbuch"
require "semantic_version"
require "uri"
require "uuid"

include Logbuch::Annotations

struct SemanticVersion
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new("own #{self}")
  end
end

# A value type that is a class takes no level of nesting with a `to_trace` of
# its own too, so when that converts itself again only the depth ceiling stops
# it.
class Time::Location
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"self" => tracer.convert(self)})
  end
end

class PrintBackend < Log::Backend
  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    puts "args: #{entry.data[:args]}" if entry.data[:args]?
  end
end

Log.setup(:trace, PrintBackend.new)

class Lookup
  @[Logged(:id)]
  def find(id : UUID) : Nil
  end
end

id = UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
puts "id: #{Logbuch.convert(id, detail: :id).as_s}"
puts "uri: #{Logbuch.convert(URI.parse("https://example.com/a"), detail: :id).as_s}"
Lookup.new.find(id)
puts "own: #{Logbuch.convert(SemanticVersion.new(1, 2, 3), detail: :id).as_s}"
value = Logbuch.convert(Time::Location::UTC, detail: :full)
levels = 0
while inner = value.as_h?.try(&.["self"]?)
  value = inner
  levels += 1
end
puts "ceiling: #{levels} levels, then #{value.as_s.sub(/0x[0-9a-f]+/, "0x…")}"
Logbuch.configure { max_depth 0 }
puts "depth 0: #{Logbuch.convert(URI.parse("https://example.com/a"), detail: :full).as_s}"
