require "path"
require "set"
require "uri"

require "../spec_helper"
require "../support/samples"

alias NestedList = Array(NestedList) | Int32
alias NestedMap = Hash(String, NestedMap) | Int32
alias NestedDeque = Deque(NestedDeque) | Int32

@[Logbuch::Annotations::LogType]
class Chain
  getter name : String
  property next_chain : Chain?

  def initialize(@name : String, @next_chain : Chain? = nil)
  end
end

# A chain of hops, logged by its fields.
@[Logbuch::Annotations::LogType]
class Hop
  getter next_hop : Hop?

  def initialize(@next_hop : Hop? = nil)
  end
end

@[Logbuch::Annotations::LogType]
class Pair
  getter left : Card
  getter right : Card

  def initialize(@left : Card, @right : Card)
  end
end

class Holder
  getter lock = Mutex.new
  getter fiber : Fiber = Fiber.current
  getter name = "holder"
end

@[Logbuch::Annotations::LogType]
class FieldHolder
  getter lock = Mutex.new
  getter output : IO = STDOUT
  getter fiber : Fiber = Fiber.current
  getter name = "holder"
end

# Returns the nesting depth of a converted value, following the given key.
def depth_of(value : Log::Metadata::Value, key : String) : Int32
  depth = 0
  while (hash = value.as_h?) && (inner = hash[key]?)
    depth += 1
    value = inner
  end
  depth
end

# The link *steps* links after *head*.
def chain_link(head : Chain, steps : Int) : Chain
  steps.times { head = head.next_chain || raise SampleError.new("the chain ends early") }
  head
end

# Not opted in, so logged with inspect.
class LooseChain
  getter next_chain : LooseChain?

  def initialize(@next_chain : LooseChain? = nil)
  end
end

# Not opted in, so logged with inspect.
class LooseBag
  getter numbers : Array(Int32)

  def initialize(@numbers : Array(Int32))
  end
end

# Takes `length:` on every parameter whose value it may cut: a string, a
# parameter without a type, a union, and an object logged with `inspect`.
class Notes
  include Logbuch::Annotations

  @[Logged]
  def take(
    @[LogAs(length: 3)] text : String,
    @[LogAs(length: 3)] anything,
    @[LogAs(length: 3)] either : Int32 | String,
    @[LogAs(length: 8)] bag : LooseBag,
  ) : Nil
  end
end

# With a field marked `:id`, so its identity shows that field.
class Badge
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter owner = Chain.new("0", Chain.new("1"))
end

# Takes the limits that still apply at `:id`: `length:` on a string, on a
# value type and on an object, whose identity it cuts. A field's detail only
# sets from which detail it is shown, so `length:` on a field marked `:id`
# cuts the `inspect` text at `Summary` and the identity at `Id`, and is
# accepted on an object logged by its fields, which logs a hash at `Summary`.
class IdNotes
  include Logbuch::Annotations

  @[Logged(:id)]
  def take(
    @[LogAs(length: 3)] text : String,
    @[LogAs(length: 4)] path : Path,
    @[LogAs(length: 10)] badge : Badge,
  ) : Nil
  end

  @[LogAs(:id, length: 8)]
  getter bag = LooseBag.new([1, 2, 3])

  @[LogAs(:id, length: 5)]
  getter card = Card.new
end

@[Logbuch::Annotations::LogType]
class Report
  include Logbuch::Annotations

  @[LogAs(:summary, cap: 2)]
  getter tags = ["a", "b", "c", "d"]

  @[LogAs(:summary, length: 5)]
  getter title = "abcdefghij"

  @[LogAs(:summary, cap: 1)]
  getter inner = {"x" => ["p", "q", "r"], "y" => ["s"]}

  @[LogAs(:summary, length: 2)]
  getter nested_failure = Exception.new("abcdef", cause: KeyError.new("ghijkl"))

  @[LogAs(:summary, length: 3)]
  getter nickname : String? = "abcdef"

  getter other = ["a", "b", "c"]

  @[LogAs(:full, length: 8)]
  getter bag = LooseBag.new([1, 2, 3])

  @[LogAs(:summary, length: 5)]
  getter failure = ArgumentError.new("abcdefghij")

  @[LogAs(:summary, length: 3)]
  getter keyed = {"abcdef" => "abcdef"}

  @[LogAs(:summary, cap: 1)]
  getter dotted = {"…" => 1, "x" => 2, "y" => 3}
end

# A set and a deque, each limited to two items.
@[Logbuch::Annotations::LogType]
class Pantry
  include Logbuch::Annotations

  @[LogAs(:full, cap: 2)]
  getter spices = Set{"a", "b", "c", "d"}

  @[LogAs(:full, cap: 2)]
  getter queue = Deque{1, 2, 3}
end

# A struct logged by its fields, without an `:id` field.
@[Logbuch::Annotations::LogType]
struct DepthSpot
  getter x : Int32
  getter y : Int32

  def initialize(@x : Int32 = 1, @y : Int32 = 2)
  end
end

# A struct logged by its fields, identified by its `:id` field.
struct DepthTag
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter code : String = "t1"

  getter weight : Int32 = 3
end

# Not opted in, so logged with inspect.
struct DepthLoose
  getter x : Int32 = 1
end

# A struct holding another, which sits a level deeper.
@[Logbuch::Annotations::LogType]
struct DepthBox
  getter spot = DepthSpot.new
  getter name = "box"
end

enum DepthColor
  Red
end

# A value type of the program, with a `to_trace` of its own.
struct DepthSku
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    tracer.convert("sku-1", length: tracer.length)
  end
end

# A class with a `to_trace` of its own, which takes a level all the same.
class DepthWallet
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    tracer.convert("12.50 EUR")
  end
end

# A struct whose fields hold no other values.
@[Logbuch::Annotations::LogType]
struct DepthReading
  getter count = 7
  getter ratio = 0.5
  getter? flag = true
  getter none : Nil = nil
  getter letter = 'a'
  getter unit = :celsius
  getter color = DepthColor::Red
  getter label = "kitchen"
  getter at = Time.utc(2026, 1, 2)
  getter span = 1.second
  getter path = Path["/srv"]
  getter uri = URI.parse("https://example.com/a")
  getter location = Time::Location.fixed("CET", 3600)
  getter sku = DepthSku.new
end

# Structs, tuples and other values for the depth limit, each converted on its
# own with `convert_at_depth`.
class DepthHolder
  getter spot = DepthSpot.new
  getter tag = DepthTag.new
  getter loose = DepthLoose.new
  getter box = DepthBox.new
  getter reading = DepthReading.new
  getter time = Time.utc(2026, 1, 2)
  getter sku = DepthSku.new
  getter pair = {DepthSpot.new, 1}
  getter pairs = {DepthSpot.new, 1}
  getter spots = [DepthSpot.new]
  getter named = {spot: DepthSpot.new, count: 1}
  getter set = Set{1, 2}
  getter slice : Slice(Int32) = Slice[1, 2]
  getter uri = URI.parse("https://example.com/a")
  getter location = Time::Location.fixed("CET", 3600)
  getter chain = Chain.new("0")
  getter list = [1, 2]
  getter map = {"a" => 1}
  getter queue = Deque{1, 2}
  getter wallet = DepthWallet.new
end

# Converts *value* at `Full` with `max_depth` set to *depth*.
def convert_at_depth(value, depth : Int) : Log::Metadata::Value
  with_max_depth(depth) { Logbuch.convert(value, detail: :full) }
end

# The values of *holder*, each converted on its own with `max_depth` 0, at
# the depth limit, or 1, which shows the value and cuts what is inside it.
def depth_values(holder : DepthHolder) : Hash(String, Log::Metadata::Value)
  {
    "spot"     => convert_at_depth(holder.spot, 0),
    "tag"      => convert_at_depth(holder.tag, 0),
    "loose"    => convert_at_depth(holder.loose, 0),
    "box"      => convert_at_depth(holder.box, 1),
    "reading"  => convert_at_depth(holder.reading, 1),
    "time"     => convert_at_depth(holder.time, 0),
    "sku"      => convert_at_depth(holder.sku, 0),
    "pair"     => convert_at_depth(holder.pair, 0),
    "pairs"    => convert_at_depth(holder.pairs, 1),
    "spots"    => convert_at_depth(holder.spots, 1),
    "named"    => convert_at_depth(holder.named, 1),
    "set"      => convert_at_depth(holder.set, 0),
    "slice"    => convert_at_depth(holder.slice, 0),
    "uri"      => convert_at_depth(holder.uri, 0),
    "location" => convert_at_depth(holder.location, 0),
    "chain"    => convert_at_depth(holder.chain, 0),
    "list"     => convert_at_depth(holder.list, 0),
    "map"      => convert_at_depth(holder.map, 0),
    "queue"    => convert_at_depth(holder.queue, 0),
    "wallet"   => convert_at_depth(holder.wallet, 0),
  }
end

# Not opted in, and its inspect carries on when writing raises.
class GuardedInspect
  getter failures = 0

  def inspect(io : IO) : Nil
    io << "x" * 2000
  rescue
    @failures += 1
  end
end

describe TraceLimits do
  test "an array that contains itself is cut off at the repeat" do
    list = [1] of NestedList
    list << list
    value = Logbuch.convert(list, detail: :full).as_a
    assert value[0].as_i == 1
    assert value[1].as_s == "#<Array:0x#{list.object_id.to_s(16)}>"
  end

  test "a hash that contains itself is cut off at the repeat" do
    map = {"one" => 1} of String => NestedMap
    map["self"] = map
    keys, values = pair_parts(Logbuch.convert(map, detail: :full))
    assert keys.map(&.as_s) == ["one", "self"]
    assert values[0].as_i == 1
    assert values[1].as_s == "#<Hash:0x#{map.object_id.to_s(16)}>"
  end

  test "a deque that contains itself is cut off at the repeat" do
    deque = Deque(NestedDeque).new
    deque << 1
    deque << deque
    assert Logbuch.convert(deque, detail: :full).as_a[1].as_s == "#<Deque:0x#{deque.object_id.to_s(16)}>"
  end

  test "an object that appears twice without a cycle is shown twice" do
    card = Card.new
    value = Logbuch.convert(Pair.new(card, card), detail: :full).as_h
    assert value["left"].as_h["id"].as_s == "c1"
    assert value["right"].as_h["id"].as_s == "c1"
  end

  test "a deep object graph stops at the depth limit" do
    head = Chain.new("0")
    100_000.times { |i| head = Chain.new((i + 1).to_s, head) }
    value = Logbuch.convert(head, detail: :full)
    assert depth_of(value, "next_chain") == Logbuch::MAX_DEPTH
    cut = chain_link(head, Logbuch::MAX_DEPTH)
    assert value.to_s.includes?(%("next_chain" => "#<Chain:0x#{cut.object_id.to_s(16)}>"))
  end

  test "a long collection keeps the first items and counts the rest" do
    value = Logbuch.convert((1..1000).to_a, detail: :summary).as_a
    assert value.size == Logbuch::MAX_CAP + 1
    assert value[0].as_i == 1
    assert value.last.as_s == "… 900 more"
  end

  test "a long hash keeps the first entries and counts the rest" do
    hash = (1..250).to_h { |i| {i, i} }
    value = Logbuch.convert(hash, detail: :summary).as_a
    assert value.size == Logbuch::MAX_CAP + 1
    assert value.last.as_s == "… 150 more"
  end

  test "a tuple reports all its elements, beyond the item limit" do
    tuple = {% begin %}{ {% for i in 1..150 %}{{ i }}, {% end %} }{% end %}
    value = Logbuch.convert(tuple, detail: :summary).as_a
    assert value.size == 150
    assert value.last.as_i == 150
  end

  test "a named tuple reports all its fields, beyond the item limit" do
    named = {% begin %}{ {% for i in 1..150 %}key{{ i }}: {{ i }}, {% end %} }{% end %}
    value = Logbuch.convert(named, detail: :summary).as_h
    assert value.size == 150
    assert value["key150"].as_i == 150
  end

  test "no value nests deeper than the depth ceiling, the largest max_depth" do
    hop = Hop.new
    hops = [hop]
    300.times { hops << (hop = Hop.new(hop)) }
    value = convert_at_depth(hop, Logbuch::DEPTH_CEILING)
    levels = 0
    while (hash = value.as_h?) && (inner = hash["next_hop"]?)
      value = inner
      levels += 1
    end
    assert levels == Logbuch::DEPTH_CEILING
    assert value.as_s == "#<Hop:0x#{hops[-1 - Logbuch::DEPTH_CEILING].object_id.to_s(16)}>"
  end

  test "a field annotation sets the limits for its value" do
    report = Report.new
    value = Logbuch.convert(report, detail: :full).as_h
    assert value["tags"].as_a.map(&.as_s) == ["a", "b", "… 2 more"]
    assert value["title"].as_s == "abcde… (+5 bytes)"
    assert value["failure"].as_h["message"].as_s == "abcde… (+5 bytes)"
  end

  test "item and length limits apply to the annotated value only, not to what is inside it" do
    value = Logbuch.convert(Report.new, detail: :full).as_h
    inner = value["inner"].as_a
    assert inner[0].as_a[0].as_s == "x"
    assert inner[0].as_a[1].as_a.map(&.as_s) == ["p", "q", "r"]
    assert inner[1].as_s == "… 1 more"
    failure = value["nested_failure"].as_h
    assert failure["message"].as_s == "ab… (+4 bytes)"
    assert failure["cause"].as_h["message"].as_s == "ghijkl"
    assert value["other"].as_a.map(&.as_s) == ["a", "b", "c"]
  end

  test "the depth limit is counted down through the children of a value" do
    chain = Chain.new("0", Chain.new("1", Chain.new("2", Chain.new("3"))))
    deep = convert_at_depth(chain, 3)
    assert depth_of(deep, "next_chain") == 3
    cut = chain_link(chain, 3)
    assert deep.to_s.includes?(%("next_chain" => "#<Chain:0x#{cut.object_id.to_s(16)}>"))
  end

  test "a struct past the depth limit is logged as its identity" do
    holder = DepthHolder.new
    value = depth_values(holder)
    assert value["spot"].as_s == "#<DepthSpot>"
    assert value["spot"].as_s == Logbuch.convert(holder.spot, detail: :id).as_s
    assert value["tag"].as_s == "t1"
    assert value["loose"].as_s == "DepthLoose(@x=1)"
    assert value["loose"].as_s == Logbuch.convert(holder.loose, detail: :id).as_s
  end

  test "a depth limit is counted down through the structs inside a struct" do
    holder = DepthHolder.new
    box = depth_values(holder)["box"].as_h
    assert box["name"].as_s == "box"
    assert box["spot"].as_s == Logbuch.convert(holder.box.spot, detail: :id).as_s
  end

  test "values that hold no other values are logged by value at the depth limit" do
    value = depth_values(DepthHolder.new)
    reading = value["reading"].as_h
    assert reading["count"].as_i == 7
    assert reading["ratio"].raw == 0.5
    assert reading["flag"].as_bool == true
    assert reading["none"].raw.nil?
    assert reading["letter"].as_s == "'a'"
    assert reading["unit"].as_s == "celsius"
    assert reading["color"].as_s == "Red"
    assert reading["label"].as_s == "kitchen"
    assert reading["at"].as_time == Time.utc(2026, 1, 2)
    assert reading["span"].as_s == "00:00:01"
    assert reading["path"].as_s == "/srv"
    assert reading["uri"].as_s == "https://example.com/a"
    assert reading["location"].as_s == "CET"
    assert reading["sku"].as_s == "sku-1"
    assert value["time"].as_time == Time.utc(2026, 1, 2)
    assert value["sku"].as_s == "sku-1"
    assert value["uri"].as_s == "https://example.com/a"
    assert value["location"].as_s == "CET"
  end

  test "a tuple, a named tuple, a set and a slice take a level of nesting, like an array" do
    holder = DepthHolder.new
    value = depth_values(holder)
    spot = Logbuch.convert(DepthSpot.new, detail: :id).as_s
    assert value["pair"].as_s == "#<Tuple>"
    assert value["pairs"].as_a.map(&.raw) == [spot, 1]
    assert value["spots"].as_a.map(&.raw) == [spot]
    assert value["named"].as_h.transform_values(&.raw) == {"spot" => spot, "count" => 1}
    assert value["set"].as_s == "#<Set>"
    assert value["slice"].as_s == "#<Slice>"
  end

  test "an object, an array, a hash, a deque and an object with a to_trace of its own take a level of nesting" do
    holder = DepthHolder.new
    value = depth_values(holder)
    assert value["chain"].as_s == "#<Chain:0x#{holder.chain.object_id.to_s(16)}>"
    assert value["list"].as_s == "#<Array:0x#{holder.list.object_id.to_s(16)}>"
    assert value["map"].as_s == "#<Hash:0x#{holder.map.object_id.to_s(16)}>"
    assert value["queue"].as_s == "#<Deque:0x#{holder.queue.object_id.to_s(16)}>"
    assert value["wallet"].as_s == "#<DepthWallet:0x#{holder.wallet.object_id.to_s(16)}>"
  end

  test "limit options on :omit, on :redacted, or with a bad value fail to compile" do
    assert compile_error("limit_on_omit").to_s.includes?("logbuch: cap: has no effect on :omit")
    assert compile_error("limit_on_redact").to_s.includes?("logbuch: length: has no effect on :redacted, which logs \"***\"")
    assert compile_error("limit_not_a_number").to_s.includes?("logbuch: cap: takes a non-negative integer")
    assert compile_error("limit_float").to_s.includes?("logbuch: length: takes a non-negative integer, on field Offender@name")
    assert compile_error("limit_above_uint32").to_s.includes?("logbuch: cap: takes at most 4294967295, on")
  end

  test "length: on a value it cannot cut fails to compile" do
    assert compile_error("length_on_collection").to_s.includes?("logbuch: length: has no effect on Array(String): it cuts a string or inspect text only, not the values inside a collection; use items(length: ...), on parameter tags of Offender#go")
    assert compile_error("length_on_splat").to_s.includes?("logbuch: length: has no effect on Tuple: it cuts a string or inspect text only, not the values inside a collection; use items(length: ...), on parameter names of Offender#go")
    assert compile_error("length_on_number").to_s.includes?("logbuch: length: has no effect on Int32: it cuts a string or inspect text only, on field Offender@count")
    assert compile_error("length_on_fields").to_s.includes?("logbuch: length: has no effect on FullName, which is logged by its fields: it cuts a string or inspect text only; put length: on the fields, on field Offender@name")
    assert compile_error("length_on_fields_param").to_s.includes?("logbuch: length: has no effect on Account, which is logged by its fields: it cuts a string or inspect text only; put length: on the fields, on parameter account of Offender#go")
    assert compile_error("length_on_char").to_s.includes?("logbuch: length: has no effect on Char: it cuts a string or inspect text only, on parameter letter of Offender#go")
  end

  test "length: is accepted at :id, where it cuts strings, value types and identities" do
    args = capture_log { IdNotes.new.take("abcdef", Path["/tmp/abc"], Badge.new) }[0].data[:args].as_h
    assert args["text"].as_s == "abc… (+3 bytes)"
    assert args["path"].as_s == "/tmp…"
    assert args["badge"].as_s == "#<Chain:0x…"
    summary = Logbuch.convert(IdNotes.new, detail: :summary).as_h
    assert summary["bag"].as_s == "#<LooseB…"
    assert summary["card"].as_h["id"].as_s == "c1"
    assert Logbuch.convert(IdNotes.new, detail: :id).as_h.transform_values(&.as_s) == {"bag" => "#<LooseB…", "card" => "c1"}
  end

  test "cap: on a value that is not a collection fails to compile" do
    assert compile_error("cap_on_string").to_s.includes?("logbuch: cap: has no effect on String, which is not an array, deque, set, slice or hash: it limits the items of a collection only, on parameter name of Offender#go")
    assert compile_error("cap_on_object").to_s.includes?("logbuch: cap: has no effect on Loose, which is not an array, deque, set, slice or hash: it limits the items of a collection only, on field Offender@loose")
  end

  test "length: is accepted wherever the value may be a string or inspect text" do
    args = capture_log { Notes.new.take("abcdef", "ghijkl", "mnopqr", LooseBag.new([1, 2, 3])) }[0].data[:args].as_h
    assert args["text"].as_s == "abc… (+3 bytes)"
    assert args["anything"].as_s == "ghi… (+3 bytes)"
    assert args["either"].as_s == "mno… (+3 bytes)"
    assert args["bag"].as_s == "#<LooseB…"
    args = capture_log { Notes.new.take("abc", 123456, 123456, LooseBag.new([1])) }[0].data[:args].as_h
    assert args["anything"].as_i == 123456
    assert args["either"].as_i == 123456
    assert Logbuch.convert(Report.new, detail: :full).as_h["nickname"].as_s == "abc… (+3 bytes)"
  end

  test "limits are unsigned, so a negative one fails to compile" do
    assert typeof(Logbuch::MAX_DEPTH, Logbuch::MAX_CAP, Logbuch::MAX_LENGTH, Logbuch::DEPTH_CEILING) == UInt32
    output = compile_error("negative_convert_limit").to_s
    assert output.includes?("no overload matches 'Logbuch::Tracer#convert'")
    assert output.includes?("cap : UInt32 | ::Nil")
  end

  test "inspect of a deep graph stops at the length limit instead of overflowing the stack" do
    head = LooseChain.new
    100_000.times { head = LooseChain.new(head) }
    value = Logbuch.convert(head, detail: :full).as_s
    assert value.starts_with?("#<LooseChain")
    assert value.ends_with?("…")
    assert value.size == Logbuch::MAX_LENGTH + 1
  end

  test "inspect of a large object is cut at the length limit" do
    value = Logbuch.convert(LooseBag.new((1..1_000_000).to_a), detail: :full).as_s
    assert value.size == Logbuch::MAX_LENGTH + 1
    assert value.ends_with?("…")
  end

  test "a length option cuts the inspect text of its value" do
    value = Logbuch.convert(Report.new, detail: :full).as_h
    assert value["bag"].as_s == "#<LooseB…"
  end

  test "a long string of multibyte characters is cut at a character and counts the bytes left" do
    value = Logbuch.convert("ä" * 1500, detail: :full).as_s
    assert value == "#{"ä" * Logbuch::MAX_LENGTH}… (+952 bytes)"
  end

  test "a string with more bytes than the limit but few characters is not cut" do
    value = Logbuch.convert("ä" * Logbuch::MAX_LENGTH, detail: :full).as_s
    assert value == "ä" * Logbuch::MAX_LENGTH
  end

  test "hash keys are cut to the length limit" do
    cut = "k" * Logbuch::MAX_LENGTH + "… (+976 bytes)"
    assert pair_keys(Logbuch.convert({"k" * 2000 => 1}, detail: :full)) == [cut]
    pairs = Logbuch.convert({"k" * 2000 => 1, ["k" * 2000] => 2}, detail: :full).as_a
    assert pairs[0].as_a[0].as_s == cut
    assert pairs[1].as_a[0].as_a[0].as_s == cut
  end

  test "a length option cuts the keys of its hash" do
    value = Logbuch.convert(Report.new, detail: :full).as_h
    assert value["keyed"].as_a.map(&.as_a.map(&.as_s)) == [["abc… (+3 bytes)", "abcdef"]]
  end

  test "a hash key … stays a key, and the rest is counted in a last item" do
    dotted = Logbuch.convert(Report.new, detail: :full).as_h["dotted"].as_a
    assert dotted[0].as_a.map(&.raw) == ["…", 1]
    assert dotted[1].as_s == "… 2 more"
  end

  test "inspect text that is cut ends in … even when the inspect rescues the cut" do
    guarded = GuardedInspect.new
    value = Logbuch.convert(guarded, detail: :full).as_s
    assert guarded.failures == 1
    assert value == "x" * Logbuch::MAX_LENGTH + "…"
  end

  test "inspect text of multibyte characters is cut at a character" do
    value = Logbuch.__inspect(["ä" * 2000], 10)
    assert value == %q([") + "ä" * 8 + "…"
  end

  test "a long string is cut and the rest counted" do
    value = Logbuch.convert(("x" * 5000), detail: :summary).as_s
    assert value == "x" * Logbuch::MAX_LENGTH + "… (+3976 bytes)"
  end

  test "a large byte slice is logged like a capped list" do
    value = Logbuch.convert(Bytes.new(1_000_000, 7_u8), detail: :summary).as_a
    assert value.size == Logbuch::MAX_CAP + 1
    assert value.last.as_s == "… 999900 more"
  end

  test "an unannotated object holding a locked mutex is logged with inspect" do
    holder = Holder.new
    value = holder.lock.synchronize { Logbuch.convert(holder, detail: :full) }.as_s
    assert value.starts_with?("#<Holder")
  end

  test "stdlib objects in an annotated object are logged with inspect, even with the lock held" do
    holder = FieldHolder.new
    value = holder.lock.synchronize { Logbuch.convert(holder, detail: :full) }.as_h
    assert value["lock"].as_s.starts_with?("#<Sync::Mutex")
    assert value["output"].as_s.starts_with?("#<IO::FileDescriptor")
    assert value["fiber"].as_s.starts_with?("#<Fiber")
    assert value["name"].as_s == "holder"
  end

  test "a set and a deque keep the first items and count the rest" do
    value = Logbuch.convert(Pantry.new, detail: :full).as_h
    assert value["spices"].as_a.map(&.as_s) == ["a", "b", "… 2 more"]
    assert value["queue"].as_a.map(&.to_s) == ["1", "2", "… 1 more"]
  end

  test "the limits the build does not check compile" do
    success, output = compile_output("compiles/unchecked_limits")
    puts output unless success
    assert success
  end
end
