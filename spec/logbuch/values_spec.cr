require "../spec_helper"
require "../../src/logbuch"
# Required after logbuch, which finds them all the same.
require "big"
require "complex"
require "mime/media_type"
require "semantic_version"
require "socket"
require "uri"
require "uuid"

enum Color
  Red
end

class WrappedError < Exception
end

# A struct used as a hash key, with a password its `inspect` and `to_s` show.
struct KeyAccount
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter id : String
  @[LogAs(:redacted)]
  getter password : String

  def initialize(@id : String, @password : String)
  end
end

# A class used as a hash key, logged by its fields, whose own `to_s` shows its
# token.
class KeySession
  include Logbuch::Annotations

  getter user : String
  @[LogAs(:redacted)]
  getter token : String

  def initialize(@user : String, @token : String)
  end

  def to_s(io : IO) : Nil
    io << "session " << @user << ' ' << @token
  end
end

# A struct used as a hash key without `:id` fields, with a redacted pin.
struct KeyBadge
  include Logbuch::Annotations

  getter holder : String
  @[LogAs(:redacted)]
  getter pin : String

  def initialize(@holder : String, @pin : String)
  end
end

# A class that is a key of its own hash, so converting it meets itself.
@[Logbuch::Annotations::LogType]
class KeyNode
  getter name = "n"
  getter peers = {} of KeyNode => Int32
end

# A class with a hash of objects whose keys the `length:` of the field cuts.
class KeyLedger
  include Logbuch::Annotations

  @[LogAs(:summary, length: 12)]
  getter accounts = {KeyAccount.new("account-number-1", "hunter2") => 1}
end

# A struct used as a hash key, with two `:id` fields.
struct KeySeat
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter row : Int32
  @[LogAs(:id)]
  getter letter : String
  getter price = 40

  def initialize(@row : Int32, @letter : String)
  end
end

# A struct used as a hash key, whose `:id` field holds a value of type *T*.
struct KeyTicket(T)
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter holder : T

  def initialize(@holder : T)
  end
end

# A struct that did not opt in, held in a key's `:id` field.
struct KeyPoint
  getter x = 1
end

# A class used as a hash key, whose `:id` field may lead back to it.
class KeyPeer
  include Logbuch::Annotations

  @[LogAs(:id)]
  property peer : KeyPeer?
end

# One of each type in `Logbuch::VALUE_TYPES`, with the text each logs.
VALUE_SAMPLES = [
  {Complex.new(1.5, -2), "1.5 - 2.0i"},
  {MIME::MediaType.parse("text/html; charset=utf-8"), "text/html; charset=utf-8"},
  {Path["/tmp/a b"], "/tmp/a b"},
  {SemanticVersion.parse("1.2.3-rc.1+build"), "1.2.3-rc.1+build"},
  {Socket::IPAddress.new("127.0.0.1", 8080), "127.0.0.1:8080"},
  {Socket::IPAddress.new("::1", 443), "[::1]:443"},
  {Socket::UNIXAddress.new("/tmp/app.sock"), "/tmp/app.sock"},
  {Time::Location.load("Europe/Berlin"), "Europe/Berlin"},
  {Time::Location::UTC, "UTC"},
  {1.5.seconds, "00:00:01.500000000"},
  {URI.parse("https://example.com:8080/a?b=c#d"), "https://example.com:8080/a?b=c#d"},
  {UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8"), "6ba7b810-9dad-11d1-80b4-00c04fd430c8"},
]

class ValueService
  include Logbuch::Annotations

  @[Logged(:id)]
  def find(id : UUID, at : URI, after : Time::Span, path : Path) : Path
    path
  end

  @[Logged]
  def cut(@[LogAs(length: 8)] id : UUID) : Nil
  end
end

describe ToTraceValues do
  test "scalars are themselves" do
    assert Logbuch.convert("a", detail: :summary) == Log::Metadata::Value.new("a")
    assert Logbuch.convert(7, detail: :summary).as_i == 7
    assert Logbuch.convert(7_i64, detail: :summary).as_i64 == 7_i64
    assert Logbuch.convert(1.5, detail: :summary).as_f64 == 1.5
    assert Logbuch.convert(true, detail: :summary).as_bool == true
    assert Logbuch.convert(nil, detail: :summary).raw.nil?
  end

  test "small integers widen, 128-bit integers become strings" do
    assert Logbuch.convert(7_i8, detail: :summary).raw.is_a?(Int32)
    assert Logbuch.convert(7_u16, detail: :summary).raw.is_a?(UInt32)
    assert Logbuch.convert(7_i128, detail: :summary).as_s == "7"
  end

  test "symbols and enums are strings" do
    assert Logbuch.convert(:sym, detail: :summary).as_s == "sym"
    assert Logbuch.convert(Color::Red, detail: :summary).as_s == "Red"
  end

  test "collections convert their elements" do
    assert Logbuch.convert([1, 2], detail: :summary).as_a.map(&.as_i) == [1, 2]
    assert(Logbuch.convert({1, "a"}, detail: :summary).as_a.size == 2)
    assert Logbuch.convert(Set{1}, detail: :summary).as_a.first.as_i == 1
  end

  test "a hash converts to key and value pairs, a named tuple to a hash" do
    assert Logbuch.convert({1 => "a"}, detail: :summary).as_a.map(&.as_a.map(&.raw)) == [[1, "a"]]
    assert(Logbuch.convert({a: 1}, detail: :summary).as_h["a"].as_i == 1)
  end

  test "exceptions carry type, message and cause" do
    error = WrappedError.new("bad", cause: KeyError.new("inner"))
    hash = Logbuch.convert(error, detail: :summary).as_h
    assert hash["type"].as_s == "WrappedError"
    assert hash["message"].as_s == "bad"
    assert hash["cause"].as_h["type"].as_s == "KeyError"
  end

  test "an exception without a message has only its type" do
    assert Logbuch.convert(WrappedError.new, detail: :summary).as_h == {"type" => Log::Metadata::Value.new("WrappedError")}
  end

  test "a Time stays a Time at every detail" do
    time = Time.utc(2026, 10, 20, 9, 30)
    [Logbuch::Detail::Id, Logbuch::Detail::Summary, Logbuch::Detail::Full].each do |detail|
      assert Logbuch.convert(time, detail: detail).raw == time
    end
  end

  test "big numbers log their text at every detail" do
    numbers = [
      {BigInt.new("123456789012345678901234567890"), "123456789012345678901234567890"},
      {BigFloat.new("1.5"), "1.5"},
      {BigDecimal.new("12.50"), "12.5"},
      {BigRational.new(1, 3), "1/3"},
    ]
    numbers.each do |number, text|
      assert [Logbuch::Detail::Id, Logbuch::Detail::Full].map { |detail| Logbuch.convert(number, detail: detail).as_s } == [text, text]
    end
  end

  test "omit yields nil for any value" do
    assert Logbuch.convert("secret", detail: :omit).raw.nil?
  end
end

describe ToTraceValueTypes do
  test "a stdlib value type logs its text at every detail" do
    VALUE_SAMPLES.each do |value, text|
      assert [Logbuch::Detail::Id, Logbuch::Detail::Summary, Logbuch::Detail::Full].map { |detail| Logbuch.convert(value, detail: detail).as_s } == [text, text, text]
    end
  end

  test "a stdlib value type logs its text at the depth limit, also one that is a class" do
    VALUE_SAMPLES.each do |value, text|
      assert with_max_depth(0) { Logbuch.convert(value, detail: :full) }.as_s == text
    end
  end

  test "a URI logs its password as ***" do
    uri = URI.parse("https://us%40er:p%3Aw@example.com/a")
    assert Logbuch.convert(uri, detail: :id).as_s == "https://us%40er:***@example.com/a"
    assert Logbuch.convert(uri, detail: :full).as_s == "https://us%40er:***@example.com/a"
    assert uri.password == "p:w"
  end

  test "a value type's text is cut to the length limit" do
    path = Path["/#{"a" * 2000}"]
    assert Logbuch.convert(path, detail: :id).as_s == "/#{"a" * 1023}…"
    uri = URI.parse("https://user:pw@example.com/#{"a" * 2000}")
    assert Logbuch.convert(uri, detail: :summary).as_s == "https://user:***@example.com/#{"a" * 995}…"
  end

  test "a traced method at id logs value types by value" do
    id = UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
    entries = capture_log { ValueService.new.find(id, URI.parse("http://a:b@host/x"), 2.seconds, Path["/srv"]) }
    assert entries[0].data[:args].as_h == {
      "id"    => Log::Metadata::Value.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8"),
      "at"    => Log::Metadata::Value.new("http://a:***@host/x"),
      "after" => Log::Metadata::Value.new("00:00:02"),
      "path"  => Log::Metadata::Value.new("/srv"),
    }
    assert entries[1].data[:result].as_s == "/srv"
  end

  test "length: cuts a value type's text" do
    entries = capture_log { ValueService.new.cut(UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8")) }
    assert entries[0].data[:args].as_h["id"].as_s == "6ba7b810…"
  end

  test "cap: on a value type fails to compile" do
    assert compile_error("cap_on_value_param").to_s.includes?("logbuch: cap: has no effect on UUID, which is not an array, deque, set, slice or hash: it limits the items of a collection only, on parameter id of Offender#go")
    assert compile_error("cap_on_value_field").to_s.includes?("logbuch: cap: has no effect on URI, which is not an array, deque, set, slice or hash: it limits the items of a collection only, on field Offender@home")
  end

  test "a value type is found when it is required after logbuch" do
    assert run_program("value_types", args: [] of String).lines == [
      "id: 6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "uri: https://example.com/a",
      "args: {\"id\" => \"6ba7b810-9dad-11d1-80b4-00c04fd430c8\"}",
      "own: own 1.2.3",
      "ceiling: #{Logbuch::DEPTH_CEILING} levels, then #<Time::Location:0x…>",
      "depth 0: https://example.com/a",
    ]
  end

  test "a program without the value types still builds and leaves them undefined" do
    assert run_program("value_types_absent", args: [] of String).lines == [
      "UUID defined: false",
      "URI defined: false",
      "path: /srv",
      "alias: Release()",
    ]
  end
end

describe HashKeys do
  test "a key with one id field logs that field's value, at every detail" do
    accounts = {KeyAccount.new("a1", "hunter2") => 1}
    assert pair_keys(Logbuch.convert(accounts, detail: :summary)) == ["a1"]
    assert pair_keys(Logbuch.convert(accounts, detail: :full)) == ["a1"]
    assert pair_keys(Logbuch.convert(accounts, detail: :id)) == ["a1"]
  end

  test "a key with several id fields logs them by name, at every detail" do
    seats = {KeySeat.new(12, "A") => 1}
    full = Logbuch.convert(seats, detail: :full).as_a
    assert full.size == 1
    assert full[0].as_a[0].as_h.transform_values(&.raw) == {"row" => 12, "letter" => "A"}
    assert full[0].as_a[1].as_i == 1
    assert pair_keys(Logbuch.convert(seats, detail: :id)) == [%({"row" => 12, "letter" => "A"})]
  end

  test "each key of a hash is logged as it converts, a primitive or not" do
    mixed = {KeySeat.new(12, "A") => 1, KeySeat.new(1, "B") => 2}
    assert Logbuch.convert(mixed, detail: :full).as_a.size == 2
    keys = Logbuch.convert({1 => "a", [2] => "b"} of Int32 | Array(Int32) => String, detail: :full).as_a.map(&.as_a[0])
    assert keys[0].as_i == 1
    assert keys[1].as_a.map(&.as_i) == [2]
  end

  test "a hash counts the entries past the item limit as a last item" do
    seats = (1..150).to_h { |row| {KeySeat.new(row, "A"), row} }
    pairs = Logbuch.convert(seats, detail: :full).as_a
    assert pairs.size == Logbuch::MAX_CAP + 1
    assert pairs.last.as_s == "… 50 more"
  end

  test "an object in a key's id field follows the key rule" do
    keys = ->(holder : KeySeat | KeyAccount | KeySession | KeyPoint) do
      pair_keys(Logbuch.convert({KeyTicket.new(holder) => 1}, detail: :summary))
    end
    assert keys.call(KeyAccount.new("a1", "hunter2")) == ["a1"]
    assert keys.call(KeySeat.new(12, "A")) == [%({"row" => 12, "letter" => "A"})]
    session = KeySession.new("ann", "hunter2")
    assert keys.call(session) == ["#<KeySession:0x#{session.object_id.to_s(16)}>"]
    assert keys.call(KeyPoint.new) == ["KeyPoint(@x=1)"]
  end

  test "id fields of keys that lead back to the key end at the repeat" do
    a = KeyPeer.new
    b = KeyPeer.new
    a.peer = b
    b.peer = a
    keys = pair_keys(Logbuch.convert({a => 1}, detail: :summary))
    assert keys == ["…"]
  end

  test "an opted-in class key without id fields logs its identity at every detail, not its fields or its own to_s" do
    session = KeySession.new("ann", "hunter2")
    {Logbuch::Detail::Id, Logbuch::Detail::Summary, Logbuch::Detail::Full}.each do |detail|
      keys, values = pair_parts(Logbuch.convert({session => 1}, detail: detail))
      assert keys.map(&.as_s) == ["#<KeySession:0x#{session.object_id.to_s(16)}>"]
      assert values.map(&.as_i) == [1]
    end
  end

  test "an opted-in struct key without id fields logs its type at every detail, so nothing of its fields shows" do
    {Logbuch::Detail::Id, Logbuch::Detail::Summary, Logbuch::Detail::Full}.each do |detail|
      badges = Logbuch.convert({KeyBadge.new("ann", "1234") => 1}, detail: detail)
      assert pair_keys(badges) == ["#<KeyBadge>"]
      assert !badges.to_s.includes?("ann")
      assert !badges.to_s.includes?("1234")
    end
  end

  test "a collection key logs its items at id" do
    session = KeySession.new("ann", "hunter2")
    keys = pair_keys(Logbuch.convert({[session] => 1}, detail: :full))
    assert keys == [%(["#<KeySession:0x#{session.object_id.to_s(16)}>"])]
  end

  test "a stdlib value type key logs its text, a URI its password as ***" do
    hash = Logbuch.convert({
      UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8") => 1,
      Path["/srv"]                                     => 2,
      URI.parse("https://ann:hunter2@example.com/")    => 3,
    }, detail: :summary)
    assert pair_keys(hash) == ["6ba7b810-9dad-11d1-80b4-00c04fd430c8", "/srv", "https://ann:***@example.com/"]
  end

  test "strings, symbols, numbers, enums, nil and Bool keys log as their values do" do
    keys = ->(value : Log::Metadata::Value) { pair_parts(value)[0].map(&.raw) }
    assert keys.call(Logbuch.convert({"a" => 1, "" => 2}, detail: :id)) == ["a", ""]
    assert keys.call(Logbuch.convert({:a => 1}, detail: :id)) == ["a"]
    assert keys.call(Logbuch.convert({1 => 1, -2 => 2}, detail: :id)) == [1, -2]
    assert keys.call(Logbuch.convert({1.5 => 1}, detail: :id)) == [1.5]
    assert keys.call(Logbuch.convert({7_i128 => 1, 8_u8 => 2}, detail: :id)) == ["7", 8_u32]
    assert keys.call(Logbuch.convert({Color::Red => 1}, detail: :id)) == ["Red"]
    assert keys.call(Logbuch.convert({nil => 1, true => 2}, detail: :id)) == [nil, true]
  end

  test "a character key logs as a character value does" do
    assert pair_keys(Logbuch.convert({'a' => 1}, detail: :summary)) == ["'a'"]
  end

  test "a key that leads back to an object being converted is cut as a cycle, as its identity" do
    node = KeyNode.new
    node.peers[node] = 1
    peers = Logbuch.convert(node, detail: :full).as_h["peers"]
    assert pair_keys(peers) == ["#<KeyNode:0x#{node.object_id.to_s(16)}>"]
  end

  test "a collection key logs its converted items within the item limit" do
    keys = pair_keys(Logbuch.convert({[1, 2] => 1, {1, "a"} => 2, (1..200).to_a => 3}, detail: :summary))
    assert keys[0, 2] == ["[1, 2]", %([1, "a"])]
    assert keys[2].ends_with?(%(99, 100, "… 100 more"]))
  end

  test "each string of a key is cut to the hash's length limit" do
    hash = Logbuch.convert({KeyAccount.new("a" * 2000, "hunter2") => 1}, detail: :summary)
    assert pair_keys(hash) == ["a" * Logbuch::MAX_LENGTH + "… (+976 bytes)"]
    ledger = Logbuch.convert(KeyLedger.new, detail: :summary).as_h
    assert pair_keys(ledger["accounts"]) == ["account-numb… (+4 bytes)"]
    seats = Logbuch.convert({KeySeat.new(1, "a" * 2000) => 1}, detail: :summary).as_a
    assert seats[0].as_a[0].as_h["letter"].as_s == "a" * Logbuch::MAX_LENGTH + "… (+976 bytes)"
  end
end

describe HashPairs do
  test "two keys that convert to the same value keep both entries" do
    keys, values = pair_parts(Logbuch.convert({KeyBadge.new("ann", "1") => 1, KeyBadge.new("bob", "2") => 2}, detail: :full))
    assert keys.map(&.as_s) == ["#<KeyBadge>", "#<KeyBadge>"]
    assert values.map(&.as_i) == [1, 2]
    long = "a" * 2000
    keys, _ = pair_parts(Logbuch.convert({long + "x" => 1, long + "y" => 2}, detail: :summary))
    cut = long[0, Logbuch::MAX_LENGTH] + "… (+977 bytes)"
    assert keys.map(&.as_s) == [cut, cut]
  end

  test "keys of the same text keep their converted values" do
    keys, values = pair_parts(Logbuch.convert({1 => "a", "1" => "b"} of Int32 | String => String, detail: :summary))
    assert keys.map(&.raw) == [1, "1"] of Int32 | String
    assert values.map(&.as_s) == ["a", "b"]
    keys, _ = pair_parts(Logbuch.convert({nil => 1, "" => 2} of String? => Int32, detail: :summary))
    assert keys.map(&.raw) == [nil, ""] of String?
  end

  test "an empty hash converts to an empty array" do
    assert Logbuch.convert({} of String => Int32, detail: :summary).as_a.empty?
  end
end

describe OwnPrelude do
  test "a program with a prelude of its own traces and converts, and the types logbuch does not use stay undefined" do
    assert run_program("own_prelude", args: [] of String).lines == [
      %(>Calculator#add {"left" => 1, "right" => 2}),
      "<Calculator#add 3",
      %(tuple: [1, "a"]),
      %(hash: [["k", "'c'"]]),
      "deque: [1, 2]",
      "path: /srv",
      "undefined: Complex Set SemanticVersion URI UUID",
    ]
  end

  test "a collection required after logbuch still logs its items" do
    assert run_program("own_prelude_set", args: [] of String).lines == ["set: [1, 2]"]
  end
end
