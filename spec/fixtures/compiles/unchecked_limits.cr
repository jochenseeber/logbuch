require "../../../src/logbuch"

# The limit options the build does not check, which compile though they may
# have no effect.

# A value type with a `to_trace` of its own, which decides what the limits do.
struct Sku
  def initialize(@code : String)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    tracer.convert(@code, length: tracer.length)
  end
end

# Not opted in, so logged with `inspect`.
class Loose
  @name = "loose"
end

class Shelf
  include Logbuch::Annotations

  @[LogAs(:full, cap: 2, length: 3)]
  getter sku = Sku.new("ABCDEF")

  @[LogAs(:full, items(:id, cap: 1, length: 3))]
  getter other_sku = Sku.new("GHIJKL")

  @[LogAs(:full, length: 3)]
  getter loose = Loose.new

  # Not traced, so its parameters are logged nowhere.
  def count(@[LogAs(length: 3)] count : Int32) : Int32
    count
  end

  @[Logged]
  def take(@[LogAs(cap: 2, length: 3)] sku : Sku, @[LogAs(items(:id, cap: 1))] either : String | Int32) : Nil
  end
end

shelf = Shelf.new
shelf.count(1)
shelf.take(Sku.new("ABCDEF"), "either")
Logbuch.convert(shelf, detail: :full)
