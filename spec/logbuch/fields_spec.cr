require "../spec_helper"
require "../support/samples"

struct Plain
  getter a = 1
end

struct Marked
  include Logbuch::Annotations

  getter a = 1
  @[LogAs(:omit)]
  getter b = 2
end

@[Logbuch::Annotations::LogType]
class Group
  getter name : String = "g"
  getter members : Set(String) = Set{"a"}
end

class Session
  include Logbuch::Annotations

  getter user : String

  def initialize(@[LogAs(:omit)] @token : String = "t", @user : String = "u")
  end
end

# A redacted field is logged where it would be without the annotation: a
# string from `Summary` up, a collection only at `Full`.
# A detail next to `:redacted` sets where the masked field shows.
class Safe
  include Logbuch::Annotations

  @[LogAs(:id, :redacted)]
  getter pin : String = "1234"

  @[LogAs(:summary, :redacted)]
  getter keys : Array(String) = ["k", "l"]
end

# A converter or a limit alone keeps the field's default detail: a string
# from `Summary` up, a collection only at `Full`.
class Trimmed
  include Logbuch::Annotations

  @[LogAs(length: 3)]
  getter note : String = "word"

  @[LogAs(converter: ->(tags : Array(String)) { tags.size })]
  getter tags : Array(String) = ["a", "b"]
end

class Vault
  include Logbuch::Annotations

  @[LogAs(:redacted)]
  getter pin : String = "1234"

  @[LogAs(:redacted)]
  getter keys : Array(String) = ["k"]
end

# Details written as `Logbuch::Detail` paths.
class PathSafe
  include Logbuch::Annotations

  @[LogAs(Logbuch::Detail::Id, :redacted)]
  getter pin : String = "1234"

  @[LogAs(::Logbuch::Detail::Full)]
  getter note : String = "n"
end

class Account
  include Logbuch::Annotations

  getter name : String = "n"

  @[LogAs(:redacted)]
  getter password : String = "secret"

  @[LogAs(converter: ->(value : String) { "****#{value[-4..]}" })]
  getter card : String = "4111222233334444"

  @[LogAs(:full, converter: ->(value) { value.upcase })]
  getter note : String = "hi"

  @[LogAs(:id, converter: ->(value : String) { value.upcase })]
  getter code : String = "abc"
end

class Loose
  getter a = 1
end

# `@[LogType]` on a parent opts the subclass in too.
@[Logbuch::Annotations::LogType]
class TypedBase
  getter id = "b"
end

class TypedChild < TypedBase
  getter extra = "s"
end

@[Logbuch::Annotations::LogType]
class MarkedClass
  getter a = 1
end

class Owner
  include Logbuch::Annotations

  getter user : String

  def initialize(@user : String, @[LogAs(:omit)] @token : String)
  end
end

class Heir < Owner
end

struct SessionStruct
  include Logbuch::Annotations

  getter user : String

  def initialize(@user : String, @[LogAs(:omit)] @token : String)
  end
end

class TracedService
  include Logbuch::Tracing

  getter name = "s"
end

class TracedHeir < TracedService
end

struct TracedValue
  include Logbuch::Tracing

  getter a = 1
end

module TracedMixin
  include Logbuch::Tracing
end

class MixedIn
  include TracedMixin

  getter a = 1
end

@[Logbuch::Annotations::LogType]
class Failing
  include Logbuch::Annotations

  @[LogAs(:full, converter: ->(value : String) { raise ArgumentError.new("no #{value}") })]
  getter code = "x"
end

# Crystal copies the annotations of a method onto an instance variable the
# method assigns, so `@x` of each of these carries the `@[Logged]` of `set`.
class UntypedSetter
  include Logbuch::Annotations

  @x = 0

  @[Logged]
  def set(value : Int32) : Nil
    @x = value
  end
end

class UndeclaredSetter
  include Logbuch::Annotations

  @[Logged]
  def set(value : Int32) : Nil
    @x = value
  end
end

class InitializedSetter
  include Logbuch::Annotations

  def initialize(@x : Int32 = 0)
  end

  @[Logged]
  def set(value : Int32) : Nil
    @x = value
  end
end

class SetterUser
  include Logbuch::Annotations

  @[Logged(:full)]
  def use(untyped : UntypedSetter, undeclared : UndeclaredSetter, initialized : InitializedSetter) : Nil
  end
end

enum ShipmentState
  Packed
end

# Without field annotations, so each field is shown from its default detail:
# a value type or a string from `Summary` up, an array only at `Full`.
@[Logbuch::Annotations::LogType]
class Shipment
  getter state = ShipmentState::Packed
  getter mode = :air
  getter origin = Plain.new
  getter sent = Time.utc(2026, 10, 20)
  getter size = {2, "kg"}
  getter note : String? = "fragile"
  getter labels = ["a"]
end

# Opted in by the `@[LogAs]` on a bare instance variable declaration.
class Hideout
  @[Logbuch::Annotations::LogAs(:omit)]
  @secret = "s"

  getter name = "h"
end

# Opted in only by the `@[LogAs]` of a field, written with the full name, so
# the class neither includes `Logbuch::Annotations` nor has `@[LogType]`.
class Ancestor
  @[Logbuch::Annotations::LogAs(:id)]
  getter code = "p1"
end

class Descendant < Ancestor
  getter extra = "x"
end

# Types whose `inspect` logbuch writes, by their `inspect:` detail.
module InspectSpec
  @[Logbuch::Annotations::LogType]
  struct Badge
    include Logbuch::Annotations

    @[LogAs(:id)]
    getter holder = "Ada"
    @[LogAs(:redacted)]
    getter pin = "1234"
    getter tags = ["a"]
  end

  @[Logbuch::Annotations::LogType(inspect: :full)]
  class Account
    include Logbuch::Annotations

    getter id = "a1"
    @[LogAs(:redacted)]
    getter password = "hunter2"
    getter roles = [:admin]
    @[LogAs(:omit)]
    getter token = "t"
    @[LogAs(converter: ->(note : String) { note.size })]
    getter note = "abcdef"
  end

  # Shown at `:id`: only its `:id` field.
  @[Logbuch::Annotations::LogType(inspect: :id)]
  struct Key
    include Logbuch::Annotations

    @[LogAs(:id)]
    getter key = "k"
    getter x = 1
  end

  # Keeps Crystal's `inspect`.
  @[Logbuch::Annotations::LogType(inspect: :off)]
  struct Open
    include Logbuch::Annotations

    @[LogAs(:redacted)]
    getter pin = "1234"
  end

  # Takes `inspect: :full` from its parent.
  class Admin < Account
    getter level = 3
  end

  # Writes its own `inspect`, which wins.
  class Own
    include Logbuch::Annotations

    @[LogAs(:redacted)]
    getter pin = "1234"

    def inspect(io : IO) : Nil
      io << "own"
    end
  end

  # Not opted in, holding a value that is.
  struct Plain
    getter badge = Badge.new
  end

  # Refers to itself through a field shown at `:summary`.
  class Node
    include Logbuch::Annotations

    @[LogAs(:summary)]
    property next_node : Node?
  end

  # A lock that counts how often it is taken.
  class CountingLock
    getter count = 0

    def synchronize(&)
      @count += 1
      yield
    end
  end

  # Takes its lock while `inspect` reads its fields.
  @[Logbuch::Annotations::LogType(lock: @lock)]
  class Guarded
    getter lock = CountingLock.new
    getter name = "g"
  end
end

# The `inspect` text of *value* with each object id replaced by `0x…`.
def inspected(value) : String
  value.inspect.gsub(/0x[0-9a-f]+/, "0x…")
end

describe ToTraceFields do
  test "id shows the identity, made of the id fields only" do
    assert Logbuch.convert(Card.new, detail: :id).as_s == "c1"
  end

  test "summary shows annotated and value fields, not objects" do
    keys = Logbuch.convert(Card.new, detail: :summary).as_h.keys.sort!
    assert keys == ["active", "count", "id", "label"]
  end

  test "full shows everything except omit" do
    keys = Logbuch.convert(Card.new, detail: :full).as_h.keys.sort!
    assert keys == ["active", "count", "id", "label", "link", "mixed", "note", "owner", "tags"]
  end

  test "an unannotated set field needs full" do
    assert Logbuch.convert(Group.new, detail: :summary).as_h.keys == ["name"]
    assert Logbuch.convert(Group.new, detail: :full).as_h.has_key?("members")
  end

  test "a detail annotation on an initialize instance variable parameter applies" do
    assert Logbuch.convert(Session.new, detail: :full).as_h.keys == ["user"]
  end

  test "LogAs takes one detail and :redacted, not :omit or a converter with :redacted" do
    assert compile_error("field_positional").to_s.includes?("logbuch: @[LogAs] takes :omit, :id, :summary, :full, :redacted or items(...), not :debug, on field Offender@name")
    assert compile_error("log_as_detail_path").to_s.includes?("logbuch: @[LogAs] takes :omit, :id, :summary, :full, :redacted or items(...), not Logbuch::Detail::Most, on field Offender@name")
    assert compile_error("log_as_empty").to_s.includes?("logbuch: @[LogAs] takes a detail, :omit, :id, :summary or :full, or :redacted, or an option such as converter: or length:, on field Offender@name")
    assert compile_error("log_as_omit_redacted").to_s.includes?("logbuch: @[LogAs] takes :omit or :redacted, not both, on field Offender@pin; an omitted value is never logged")
    assert compile_error("redacted_field_with_converter").to_s.includes?("logbuch: @[LogAs] takes :redacted or converter:, not both, on field Offender@pin; :redacted always logs \"***\", and a converter that masks the value goes without it")
    assert compile_error("redacted_with_converter").to_s.includes?("logbuch: @[LogAs] takes :redacted or converter:, not both, on parameter card of Offender#go; :redacted always logs \"***\", and a converter that masks the value goes without it")
  end

  test "redact shows *** from summary detail up" do
    summary = Logbuch.convert(Account.new, detail: :summary).as_h
    assert summary["password"].as_s == "***"
    assert Logbuch.convert(Account.new, detail: :id).as_s == "ABC"
  end

  test "redact keeps the field's detail" do
    assert Logbuch.convert(Vault.new, detail: :id).as_s.starts_with?("#<Vault:0x")
    assert Logbuch.convert(Vault.new, detail: :summary).as_h == {"pin" => Log::Metadata::Value.new("***")}
    full = Logbuch.convert(Vault.new, detail: :full).as_h
    assert full["keys"].as_s == "***"
  end

  test "a detail next to :redacted sets the detail of the masked field" do
    assert Logbuch.convert(Safe.new, detail: :id).as_s == "***"
    assert Logbuch.convert(Safe.new, detail: :summary).as_h["pin"].as_s == "***"
    assert Logbuch.convert(Safe.new, detail: :summary).as_h["keys"].as_s == "***"
  end

  test "a field's detail can be a Logbuch::Detail path" do
    assert Logbuch.convert(PathSafe.new, detail: :id).as_s == "***"
    assert Logbuch.convert(PathSafe.new, detail: :summary).as_h.keys == ["pin"]
    assert Logbuch.convert(PathSafe.new, detail: :full).as_h.keys == ["pin", "note"]
  end

  test "a converter or a limit alone keeps the field's default detail" do
    assert Logbuch.convert(Trimmed.new, detail: :summary).as_h == {"note" => Log::Metadata::Value.new("wor… (+1 bytes)")}
    assert Logbuch.convert(Trimmed.new, detail: :full).as_h["tags"].as_i == 2
  end

  test "a converter changes the logged field value" do
    summary = Logbuch.convert(Account.new, detail: :summary).as_h
    assert summary["card"].as_s == "****4444"
    assert summary["code"].as_s == "ABC"
    assert !summary.has_key?("note")
    assert Logbuch.convert(Account.new, detail: :full).as_h["note"].as_s == "HI"
    assert Logbuch.convert(Account.new, detail: :id).as_s == "ABC"
  end

  test "bad converters and options on fields fail to compile" do
    assert compile_error("omit_converter").to_s.includes?("logbuch: converter: has no effect on :omit, on field Offender@name")
    assert compile_error("converter_not_a_type").to_s.includes?("logbuch: converter: takes a block in arrow notation with one parameter")
    assert compile_error("converter_two_parameters").to_s.includes?("logbuch: converter: takes a block in arrow notation with one parameter")
    assert compile_error("field_unknown_option").to_s.includes?("logbuch: unknown option color on field")
  end

  test "a field a traced method assigns is logged by its detail rules" do
    untyped, undeclared, initialized = UntypedSetter.new, UndeclaredSetter.new, InitializedSetter.new
    untyped.set(1)
    undeclared.set(2)
    initialized.set(3)
    assert Logbuch.convert(untyped, detail: :full).as_h["x"].as_i == 1
    assert Logbuch.convert(undeclared, detail: :full).as_h["x"].as_i == 2
    assert Logbuch.convert(initialized, detail: :full).as_h["x"].as_i == 3
    entries = capture_log { SetterUser.new.use(untyped, undeclared, initialized) }
    args = entries[0].data[:args].as_h
    assert args["untyped"].as_h["x"].as_i == 1
    assert args["undeclared"].as_h["x"].as_i == 2
    assert args["initialized"].as_h["x"].as_i == 3
  end

  test "a subclass of a LogType class is logged by its fields too" do
    assert Logbuch.convert(TypedChild.new, detail: :summary).as_h == {"id" => Log::Metadata::Value.new("b"), "extra" => Log::Metadata::Value.new("s")}
  end

  test "a class without annotations is logged with inspect" do
    assert Logbuch.convert(Loose.new, detail: :full).as_s.starts_with?("#<Loose")
  end

  test "a class annotated with LogType is logged by its fields" do
    assert Logbuch.convert(MarkedClass.new, detail: :full).as_h["a"].as_i == 1
  end

  test "a type that includes Logbuch::Tracing is logged by its fields" do
    assert Logbuch.convert(TracedService.new, detail: :full).as_h["name"].as_s == "s"
    assert Logbuch.convert(TracedValue.new, detail: :full).as_h["a"].as_i == 1
  end

  test "a subclass of a traced class and a type including a traced module are logged by their fields" do
    assert Logbuch.convert(TracedHeir.new, detail: :full).as_h["name"].as_s == "s"
    assert Logbuch.convert(MixedIn.new, detail: :full).as_h["a"].as_i == 1
  end

  test "a subclass keeps the detail annotations of its parent's initialize" do
    assert Logbuch.convert(Heir.new("ada", "secret"), detail: :full).as_h.keys == ["user"]
  end

  test "a struct with an annotated initialize parameter is logged by its fields" do
    assert Logbuch.convert(SessionStruct.new("ada", "secret"), detail: :full).as_h.keys == ["user"]
  end

  test "omit field never appears" do
    assert !Logbuch.convert(Card.new, detail: :full).as_h.has_key?("number")
  end

  test "a cycle logs the identity of the repeated object" do
    card = Card.new
    card.link = card
    assert Logbuch.convert(card, detail: :full).as_h["link"].as_s == "c1"
  end

  test "structs without annotations use inspect, annotated ones use fields" do
    assert Logbuch.convert(Plain.new, detail: :full).as_s == Plain.new.inspect
    assert Logbuch.convert(Marked.new, detail: :full).as_h.keys == ["a"]
  end

  test "two LogAs on a field fail to compile" do
    assert compile_error("two_field_annotations").to_s.includes?("logbuch: field Offender@name has more than one @[LogAs]")
  end

  test "level and timing on a field fail to compile" do
    assert compile_error("field_options").to_s.includes?("logbuch: level: and timing: are only allowed on methods")
  end

  test "a field converter that raises logs a placeholder" do
    assert Logbuch.convert(Failing.new, detail: :full).as_h["code"].as_s == "#<convert raised ArgumentError>"
  end

  test "value type and string fields show from summary up, an array field only at full" do
    keys = ["mode", "note", "origin", "sent", "size", "state"]
    assert Logbuch.convert(Shipment.new, detail: :summary).as_h.keys.sort! == keys
    assert Logbuch.convert(Shipment.new, detail: :full).as_h.keys.sort! == (keys + ["labels"]).sort!
  end

  test "a LogAs on a bare instance variable declaration applies" do
    assert Logbuch.convert(Hideout.new, detail: :full).as_h == {"name" => Log::Metadata::Value.new("h")}
  end

  test "a subclass is opted in by a field LogAs of its parent" do
    assert Logbuch.convert(Descendant.new, detail: :full).as_h == {"code" => Log::Metadata::Value.new("p1"), "extra" => Log::Metadata::Value.new("x")}
    assert Logbuch.convert(Descendant.new, detail: :id).as_s == "p1"
  end
end

describe MaskedInspect do
  test "an opted-in struct shows its summary fields, a redacted one as ***" do
    assert inspected(InspectSpec::Badge.new) == %(InspectSpec::Badge(@holder="Ada", @pin="***"))
    assert InspectSpec::Badge.new.to_s == InspectSpec::Badge.new.inspect
  end

  test "inspect: :full shows every field but omitted ones, converted ones as their result" do
    assert inspected(InspectSpec::Account.new) == %(#<InspectSpec::Account:0x… @id="a1", @password="***", @roles=[:admin], @note=6>)
  end

  test "inspect: :id shows only the id fields, and :off keeps Crystal's inspect" do
    assert inspected(InspectSpec::Key.new) == %(InspectSpec::Key(@key="k"))
    assert inspected(InspectSpec::Open.new) == %(InspectSpec::Open(@pin="1234"))
  end

  test "a subclass takes its parent's inspect: and its own inspect wins" do
    assert inspected(InspectSpec::Admin.new) == %(#<InspectSpec::Admin:0x… @id="a1", @password="***", @roles=[:admin], @note=6, @level=3>)
    assert InspectSpec::Own.new.inspect == "own"
  end

  test "a type that did not opt in shows an opted-in value inside it masked" do
    assert inspected(InspectSpec::Plain.new) == %(InspectSpec::Plain(@badge=InspectSpec::Badge(@holder="Ada", @pin="***")))
    assert Logbuch.convert(InspectSpec::Plain.new, detail: :summary).as_s == InspectSpec::Plain.new.inspect
  end

  test "pp shows the masked text" do
    text = String.build { |io| PrettyPrint.format(InspectSpec::Badge.new, io, 79) }
    assert text == %(InspectSpec::Badge(@holder="Ada", @pin="***"))
  end

  test "a cycle ends as Crystal's does" do
    node = InspectSpec::Node.new
    node.next_node = node
    assert inspected(node) == "#<InspectSpec::Node:0x… @next_node=#<InspectSpec::Node:0x… ...>>"
  end

  test "inspect reads the fields under the type's lock" do
    guarded = InspectSpec::Guarded.new
    assert inspected(guarded) == %(#<InspectSpec::Guarded:0x… @name="g">)
    assert guarded.lock.count == 1
  end

  test "inspect: takes a detail and fails on a type with an inspect of its own" do
    assert compile_error("inspect_unknown_detail").to_s.includes?("logbuch: inspect: takes :off, :id, :summary or :full, on @[LogType] of Offender")
    assert compile_error("inspect_own_inspect").to_s.includes?("logbuch: inspect: has no effect on Offender, which has an inspect of its own, on @[LogType] of Offender")
  end
end
