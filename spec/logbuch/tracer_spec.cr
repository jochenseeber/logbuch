require "../spec_helper"
require "../../src/logbuch"

# Two types that log each other through their own to_trace.
class Ping
  property pong : Pong?

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"pong" => tracer.convert(@pong)})
  end
end

class Pong
  property ping : Ping?

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"ping" => tracer.convert(@ping)})
  end
end

@[Logbuch::Annotations::LogType]
struct FullName
  getter first = "Alexander"
  getter tags = ["a", "b", "c"]
end

# Sets limits on values they do not apply to, which `@[LogAs]` rejects at
# build time and `Tracer#convert` accepts.
class Profile
  getter name = FullName.new
  getter pairs = {["a", "b"], ["c", "d"]}

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({
      "name"  => tracer.convert(name, length: 3, cap: 1),
      "pairs" => tracer.convert(pairs, cap: 1),
    })
  end
end

class Echoer
  include Logbuch::Annotations

  @[Logged]
  def echo(values : Array(Int32)) : Int32
    values.size
  end
end

@[Logbuch::Annotations::LogType]
class Relay
  include Logbuch::Annotations

  # The converter calls a traced method while the relay is being converted.
  @[LogAs(:full, cap: 1, converter: ->(values : Array(Int32)) { Echoer.new.echo(values); values })]
  getter values = [7, 8, 9]
end

# Converts itself again through Logbuch.convert instead of tracer.convert.
class Reentrant
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"self" => Logbuch.convert(self, detail: tracer.detail)})
  end
end

# Converts a new instance of itself through Logbuch.convert, so no object
# repeats and only the depth ceiling stops it.
class Spawner
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"next" => Logbuch.convert(Spawner.new, detail: tracer.detail)})
  end
end

# A struct that converts itself again, which no path of objects can see.
struct Mirror
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"self" => tracer.convert(self)})
  end
end

# A struct that converts itself again through Logbuch.convert.
struct ReentrantMirror
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"self" => Logbuch.convert(self, detail: tracer.detail)})
  end
end

# Converts a value through Logbuch.convert, then shows the detail and the item
# limit it was converted with.
class Nester
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    inner = Logbuch.convert([1, 2, 3], detail: :summary)
    Log::Metadata::Value.new({
      "inner"  => inner,
      "detail" => Log::Metadata::Value.new(tracer.detail.to_s),
      "cap"    => Log::Metadata::Value.new(tracer.cap.to_i32),
    })
  end
end

@[Logbuch::Annotations::LogType]
class NesterHolder
  include Logbuch::Annotations

  @[LogAs(:full, cap: 2)]
  getter nester = Nester.new
end

# Raises when it is converted.
class TraceBomb
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    raise KeyError.new("boom")
  end
end

# Converts what its blocks return instead of its values: a masked number, a
# text cut by `length:`, a block that raises and a result whose conversion
# raises.
class Masked
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({
      "card"    => tracer.convert("4111222233334444") { |number| "****#{number[-4..]}" },
      "short"   => tracer.convert("abcdef", length: 3, &.upcase),
      "raising" => tracer.convert("x") { |text| text.empty? ? text : raise ArgumentError.new(text) },
      "result"  => tracer.convert("x") { |_text| TraceBomb.new },
    })
  end
end

# A value type of the program that logs its text, cut to the length limit
# the value has, as the README shows.
struct TraceSku
  def initialize(@code : String)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    tracer.convert(@code, length: tracer.length)
  end
end

@[Logbuch::Annotations::LogType]
class SkuShelf
  include Logbuch::Annotations

  @[LogAs(:summary, length: 4)]
  getter cut = TraceSku.new("ABCDEFGH")

  getter whole = TraceSku.new("ABCDEFGH")
end

# The number of times *key* nests in *value*, and the value at the bottom.
def nesting(value : Log::Metadata::Value, key : String) : {Int32, Log::Metadata::Value}
  levels = 0
  while (hash = value.as_h?) && (inner = hash[key]?)
    value = inner
    levels += 1
  end
  {levels, value}
end

describe TracerContext do
  test "types with their own to_trace that log each other stop at the cycle" do
    ping = Ping.new
    pong = Pong.new
    ping.pong = pong
    pong.ping = ping
    value = Logbuch.convert(ping, detail: :full).as_h
    assert value["pong"].as_h["ping"].as_s == "#<Ping:0x#{ping.object_id.to_s(16)}>"
  end

  test "limits on a field do not reach the values inside a struct" do
    name = Logbuch.convert(Profile.new, detail: :full).as_h["name"].as_h
    assert name["first"].as_s == "Alexander"
    assert name["tags"].as_a.size == 3
  end

  test "limits on a field do not reach the arrays inside a tuple" do
    pairs = Logbuch.convert(Profile.new, detail: :full).as_h["pairs"].as_a
    assert pairs.map(&.as_a.size) == [2, 2]
  end

  test "a traced call inside a converter logs with the default limits" do
    entries = capture_log do
      value = Logbuch.convert(Relay.new, detail: :full).as_h
      assert value["values"].as_a.size == 2
    end
    assert entries[0].data[:args].as_h["values"].as_a.map(&.as_i) == [7, 8, 9]
  end

  test "Logbuch.convert of the value being converted stops at the cycle" do
    reentrant = Reentrant.new
    value = Logbuch.convert(reentrant, detail: :full).as_h
    assert value["self"].as_s == "#<Reentrant:0x#{reentrant.object_id.to_s(16)}>"
  end

  test "Logbuch.convert inside to_trace nests no deeper than the depth ceiling" do
    levels, bottom = nesting(Logbuch.convert(Spawner.new, detail: :full), "next")
    assert levels == Logbuch::DEPTH_CEILING
    assert bottom.as_s =~ /\A#<Spawner:0x[0-9a-f]+>\z/
  end

  test "a struct converting itself nests no deeper than the depth ceiling" do
    levels, bottom = nesting(Logbuch.convert(Mirror.new, detail: :full), "self")
    assert levels == Logbuch::DEPTH_CEILING
    assert bottom.as_s == "#<Mirror>"
  end

  test "a struct converting itself through Logbuch.convert nests no deeper than the depth ceiling" do
    levels, bottom = nesting(Logbuch.convert(ReentrantMirror.new, detail: :full), "self")
    assert levels == Logbuch::DEPTH_CEILING
    assert bottom.as_s == "#<ReentrantMirror>"
  end

  test "Logbuch.convert inside to_trace leaves the detail and limits of the conversion around it" do
    value = Logbuch.convert(NesterHolder.new, detail: :full).as_h["nester"].as_h
    assert value["inner"].as_a.map(&.as_i) == [1, 2, 3]
    assert value["detail"].as_s == "Full"
    assert value["cap"].as_i == 2
  end

  test "convert with a block converts the block's result, with the limits given" do
    value = Logbuch.convert(Masked.new, detail: :full).as_h
    assert value["card"].as_s == "****4444"
    assert value["short"].as_s == "ABC… (+3 bytes)"
  end

  test "convert with a block shows a placeholder when the block raises or converting its result does" do
    value = Logbuch.convert(Masked.new, detail: :full).as_h
    assert value["raising"].as_s == "#<convert raised ArgumentError>"
    assert value["result"].as_s == "#<to_trace raised KeyError>"
  end

  test "a to_trace reads the length limit of its value from the tracer" do
    value = Logbuch.convert(SkuShelf.new, detail: :summary).as_h
    assert value["cut"].as_s == "ABCD… (+4 bytes)"
    assert value["whole"].as_s == "ABCDEFGH"
  end
end
