require "../spec_helper"
require "../../src/logbuch"

# Opted in by `@[LogType]`, without an `:id` field.
@[Logbuch::Annotations::LogType]
class IdOrder
  getter total : Int32 = 42
  getter items : Array(String) = ["book"]
end

# Opted in, with two `:id` fields, the second holding another object.
class IdTicket
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter number : String = "t-1"

  @[LogAs(:id)]
  getter order : IdOrder = IdOrder.new

  getter seat : String = "12A"
end

# Opted in, with one `:id` field.
class IdAccount
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter code : String

  getter owner : String = "Ada"

  def initialize(@code : String = "a1")
  end
end

# Opted in through an `initialize` parameter marked `:id`.
class IdGuest
  include Logbuch::Annotations

  getter name : String

  def initialize(@[LogAs(:id)] @code : String = "g-7", @name : String = "Ada")
  end
end

# Not opted in: logged with `inspect` from `Summary` up.
class IdPlain
  getter secret = "s3cret"
end

# A generic class: its identity names the type without its type arguments.
@[Logbuch::Annotations::LogType]
class IdBox(T)
  def initialize(@value : T)
  end
end

# A struct, not opted in, so its identity is its `inspect` text.
struct IdPoint
  getter x : Int32
  getter y : Int32

  def initialize(@x : Int32 = 1, @y : Int32 = 2)
  end
end

# A struct opted in by `@[LogType]`, without an `:id` field.
@[Logbuch::Annotations::LogType]
struct IdMarkedPoint
  getter x = 1
end

# A struct, not opted in, whose `inspect` text is longer than the length limit.
struct IdLongPoint
  getter text = "a" * 2000
end

# A struct with fields logbuch never shows: a redacted and an omitted one.
struct IdPin
  include Logbuch::Annotations

  getter holder : String

  @[LogAs(:redacted)]
  getter pin : String

  def initialize(@holder : String, @pin : String, @[LogAs(:omit)] @token : String = "t")
  end
end

# A struct holding a struct with a redacted field.
struct IdWallet
  include Logbuch::Annotations

  getter pin : IdPin

  def initialize(@pin : IdPin)
  end
end

# Holds an `IdWallet`, which a depth limit of 1 cuts.
class IdWalletHolder
  include Logbuch::Annotations

  getter wallet : IdWallet

  def initialize(@wallet : IdWallet)
  end
end

# A struct without a field logbuch shows.
struct IdSecret
  include Logbuch::Annotations

  @[LogAs(:redacted)]
  getter pin : String = "1234"
end

# A struct with an `:id` field.
struct IdKeyedPoint
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter key : String = "k1"

  @[LogAs(:id)]
  getter zone : String = "eu"

  getter x : Int32 = 1
end

# Cyclic, with an `:id` field.
class IdNode
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter name : String

  @[LogAs(:summary)]
  property next_node : IdNode?

  def initialize(@name : String)
  end
end

# Cyclic, without an `:id` field.
@[Logbuch::Annotations::LogType]
class IdLink
  property next_link : IdLink?
end

# Its `:id` field holds another object of its type, so the ids may form a
# cycle.
class IdPeer
  include Logbuch::Annotations

  @[LogAs(:id)]
  property peer : IdPeer?
end

# Holds a node, which a depth limit of 2 shows one level deep.
@[Logbuch::Annotations::LogType]
class IdShallow
  getter head : IdNode

  def initialize(@head : IdNode)
  end
end

# A lock that counts how often it was taken.
class IdLockCounter
  getter count = 0

  def synchronize(&)
    @count += 1
    yield
  end
end

# Locked, without an `:id` field.
@[Logbuch::Annotations::LogType(lock: @lock)]
class IdLocked
  getter lock = IdLockCounter.new
  getter name = "l"
end

# A struct with a converted field, locked by the one holding its lock.
@[Logbuch::Annotations::LogType(lock: @lock)]
struct IdConvertedPoint
  include Logbuch::Annotations

  getter x : Int32

  @[LogAs(converter: ->(code : String) { code.size })]
  getter code : String

  getter lock : Sync::Mutex

  def initialize(@x : Int32, @code : String, @lock : Sync::Mutex = Sync::Mutex.new)
  end
end

class IdService
  include Logbuch::Annotations

  @[Logged(:id)]
  def look(order : IdOrder, ticket : IdTicket, plain : IdPlain, point : IdPoint, text : String, orders : Array(IdOrder)) : IdOrder
    order
  end

  @[Logged]
  def cut(@[LogAs(:id, length: 12)] ticket : IdTicket) : Nil
  end
end

# The identity of *value*, a class without `:id` fields, as `Detail::Id` logs
# it.
def identity(value : Reference) : String
  "#<#{value.class.name.partition("(").first}:0x#{value.object_id.to_s(16)}>"
end

describe DetailId do
  test "a class without an id field logs its type and object id" do
    order = IdOrder.new
    assert Logbuch.convert(order, detail: :id).as_s == identity(order)
    assert Logbuch.convert(order, detail: :summary).as_h.keys == ["total"]
  end

  test "a class with one id field logs that field's value" do
    assert Logbuch.convert(IdAccount.new, detail: :id).as_s == "a1"
    assert Logbuch.convert(IdGuest.new, detail: :id).as_s == "g-7"
  end

  test "several id fields log as a hash by name, an object among them as its own identity" do
    ticket = IdTicket.new
    id = Logbuch.convert(ticket, detail: :id).as_h
    assert id.keys == ["number", "order"]
    assert id["number"].as_s == "t-1"
    assert id["order"].as_s == identity(ticket.order)
  end

  test "an identity names its type without type arguments" do
    box = IdBox.new(1)
    assert Logbuch.convert(box, detail: :id).as_s == "#<IdBox:0x#{box.object_id.to_s(16)}>"
  end

  test "a class not opted in logs its inspect text, as at every other detail" do
    plain = IdPlain.new
    assert Logbuch.convert(plain, detail: :id).as_s == plain.inspect
    assert Logbuch.convert(plain, detail: :summary).as_s.includes?("s3cret")
  end

  test "a struct with id fields logs them" do
    id = Logbuch.convert(IdKeyedPoint.new, detail: :id).as_h
    assert id.transform_values(&.as_s) == {"key" => "k1", "zone" => "eu"}
  end

  test "an opted-in struct without id fields logs only its type" do
    assert Logbuch.convert(IdMarkedPoint.new, detail: :id).as_s == "#<IdMarkedPoint>"
    assert Logbuch.convert(IdSecret.new, detail: :id).as_s == "#<IdSecret>"
    assert Logbuch.convert(IdConvertedPoint.new(1, "abc"), detail: :id).as_s == "#<IdConvertedPoint>"
  end

  test "a struct not opted in logs its inspect text, cut to the length limit" do
    assert Logbuch.convert(IdPoint.new(1, 2), detail: :id).as_s == "IdPoint(@x=1, @y=2)"
    assert Logbuch.convert(IdPoint.new, detail: :summary).as_s == "IdPoint(@x=1, @y=2)"
    assert Logbuch.convert(IdLongPoint.new, detail: :id).as_s == Logbuch.convert(IdLongPoint.new, detail: :summary).as_s
    assert Logbuch.convert(IdLongPoint.new, detail: :id).as_s.size == Logbuch::MAX_LENGTH + 1
  end

  test "a struct's identity shows nothing of a redacted field, nested or not" do
    assert Logbuch.convert(IdPin.new("ada", "1234", "t1"), detail: :id).as_s == "#<IdPin>"
    assert Logbuch.convert(IdWallet.new(IdPin.new("ada", "1234")), detail: :id).as_s == "#<IdWallet>"
    assert Logbuch.convert({IdWallet.new(IdPin.new("ada", "1234"))}, detail: :id).as_a.map(&.as_s) == ["#<IdWallet>"]
    cut = with_max_depth(1) { Logbuch.convert(IdWalletHolder.new(IdWallet.new(IdPin.new("ada", "1234"))), detail: :full) }.as_h
    assert cut["wallet"].as_s == "#<IdWallet>"
  end

  test "plain values are their own identity" do
    assert Logbuch.convert("a" * 2000, detail: :id).as_s == "#{"a" * 1024}… (+976 bytes)"
    assert Logbuch.convert(7, detail: :id).as_i == 7
    assert Logbuch.convert(:sym, detail: :id).as_s == "sym"
    assert Logbuch.convert(true, detail: :id).as_bool == true
    assert Logbuch.convert(nil, detail: :id).raw.nil?
    assert Logbuch.convert('c', detail: :id).as_s == "'c'"
  end

  test "a collection logs each item as its identity" do
    orders = [IdOrder.new, IdOrder.new]
    assert Logbuch.convert(orders, detail: :id).as_a.map(&.as_s) == orders.map { |order| identity(order) }
    assert Logbuch.convert([IdAccount.new("a1"), IdAccount.new("a2")], detail: :id).as_a.map(&.as_s) == ["a1", "a2"]
    hash = Logbuch.convert({"o" => orders[0]}, detail: :id).as_a
    assert hash[0].as_a.map(&.as_s) == ["o", identity(orders[0])]
    assert Logbuch.convert({orders[0], 1}, detail: :id).as_a[0].as_s == identity(orders[0])
  end

  test "an object key logs its id field's value at id" do
    assert pair_keys(Logbuch.convert({IdAccount.new("a1") => 1}, detail: :id)) == ["a1"]
  end

  test "a cycle logs the identity of the repeated object" do
    a = IdNode.new("a")
    b = IdNode.new("b")
    a.next_node = b
    b.next_node = a
    value = Logbuch.convert(a, detail: :summary).as_h
    assert value["next_node"].as_h["next_node"].as_s == "a"
    link = IdLink.new
    other = IdLink.new
    link.next_link = other
    other.next_link = link
    value = Logbuch.convert(link, detail: :full).as_h
    assert value["next_link"].as_h["next_link"].as_s == identity(link)
  end

  test "an object past the depth limit logs its identity" do
    a = IdNode.new("a")
    b = IdNode.new("b")
    a.next_node = b
    b.next_node = IdNode.new("c")
    value = with_max_depth(2) { Logbuch.convert(IdShallow.new(a), detail: :full) }.as_h
    assert value["head"].as_h["name"].as_s == "a"
    assert value["head"].as_h["next_node"].as_s == "b"
  end

  test "id fields that lead back to the object stop at the repeat" do
    a = IdPeer.new
    b = IdPeer.new
    a.peer = b
    b.peer = a
    # Each one's id is the other's, so no value ends the chain.
    assert Logbuch.convert(a, detail: :id).as_s == "…"
    full = Logbuch.convert(a, detail: :full).as_h
    assert full["peer"].as_h["peer"].as_s == "…"
    assert Logbuch.convert(IdPeer.new, detail: :id).raw.nil?
  end

  test "the length limit cuts each string of an identity" do
    ticket = IdTicket.new
    entries = capture_log { IdService.new.cut(ticket) }
    id = entries[0].data[:args].as_h["ticket"].as_h
    order = identity(ticket.order)
    assert id["number"].as_s == "t-1"
    assert id["order"].as_s == "#{order[0, 12]}…"
  end

  test "an exception logs its type and message" do
    error = Exception.new("bad", cause: KeyError.new("inner"))
    trace = Logbuch.convert(error, detail: :id).as_h
    assert trace["type"].as_s == "Exception"
    assert trace["message"].as_s == "bad"
    assert trace["cause"].as_h["type"].as_s == "KeyError"
  end

  test "a traced method at id logs identities" do
    order = IdOrder.new
    ticket = IdTicket.new
    plain = IdPlain.new
    other = IdOrder.new
    point = IdPoint.new
    entries = capture_log { IdService.new.look(order, ticket, plain, point, "text", [other]) }
    args = entries[0].data[:args].as_h
    assert args["order"].as_s == identity(order)
    assert args["ticket"].as_h["number"].as_s == "t-1"
    assert args["ticket"].as_h["order"].as_s == identity(ticket.order)
    assert args["plain"].as_s == plain.inspect
    assert args["point"].as_s == "IdPoint(@x=1, @y=2)"
    assert args["text"].as_s == "text"
    assert args["orders"].as_a.map(&.as_s) == [identity(other)]
    assert entries[1].data[:result].as_s == identity(order)
  end

  test "a class without id fields does not take its lock at id" do
    locked = IdLocked.new
    assert Logbuch.convert(locked, detail: :id).as_s == identity(locked)
    assert locked.lock.count == 0
    Logbuch.convert(locked, detail: :summary)
    assert locked.lock.count == 1
  end
end
