require "set"

require "../spec_helper"
require "../../src/logbuch"

# An order with an `:id` field: `"o-1"` at `Id`, its id and total at
# `Summary`, its tags too at `Full`.
@[Logbuch::Annotations::LogType]
class ItemOrder
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter id : String
  getter total : Int32
  getter tags : Array(String)

  def initialize(@id : String, @total : Int32 = 1, @tags : Array(String) = ["t"])
  end
end

# Raised by the converters that fail on purpose.
class ItemConvertError < Exception
end

# Collections whose items log with options of their own.
@[Logbuch::Annotations::LogType]
class ItemCustomer
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter name = "ann"

  @[LogAs(:summary, items(:id))]
  getter orders = [ItemOrder.new("o-1"), ItemOrder.new("o-2")]

  @[LogAs(:full, items(:id))]
  getter batches = [[ItemOrder.new("o-1")], [ItemOrder.new("o-2")]]

  @[LogAs(:summary, items(:id))]
  getter by_code = {"a" => ItemOrder.new("o-1")}

  @[LogAs(:summary, items(:id))]
  getter pair = {ItemOrder.new("o-1"), ItemOrder.new("o-2")}

  @[LogAs(:summary, items(:id))]
  getter named = {first: ItemOrder.new("o-1")}

  @[LogAs(:summary, items(:id))]
  getter unique = Set{ItemOrder.new("o-1")}

  @[LogAs(:summary, items(Logbuch::Detail::Id))]
  getter by_path = [ItemOrder.new("o-1")]

  @[LogAs(:summary, items(length: 3), cap: 2)]
  getter notes = ["abcdef", "ghijkl", "mnopqr"]

  @[LogAs(:summary, items(cap: 1))]
  getter grid = [[1, 2], [3, 4]]

  @[LogAs(:summary, items(converter: ->(note : String) { note.upcase }))]
  getter shouted = {"a" => "quiet", "b" => "calm"}

  @[LogAs(:summary, items(:id), converter: ->(orders : Array(ItemOrder)) { orders.first(1) })]
  getter converted = [ItemOrder.new("o-1"), ItemOrder.new("o-2")]

  @[LogAs(:summary, items(converter: ->(note : String) { note.empty? ? note : raise ItemConvertError.new(note) }))]
  getter failing = ["", "x"]

  @[LogAs(:summary, items(:id), converter: ->(orders : Array(ItemOrder)) { raise ItemConvertError.new(orders.size.to_s) })]
  getter failing_whole = [ItemOrder.new("o-1")]

  @[LogAs(:summary, items(:id))]
  getter maybe : Array(ItemOrder)? = nil

  # An `:id` field: part of the identity, where `items(...)` has no effect.
  @[LogAs(:id, items(length: 1))]
  getter codes = ["abc"]
end

class ItemShop
  include Logbuch::Annotations

  @[Logged(:id)]
  def ship(@[LogAs(items(:full))] orders : Array(ItemOrder)) : Nil
  end

  @[Logged(:full)]
  def list(@[LogAs(items(:id), cap: 1)] orders : Array(ItemOrder)) : Nil
  end

  @[Logged]
  def index(@[LogAs(:summary, items(:id))] by_code : Hash(String, ItemOrder)) : Nil
  end

  @[Logged]
  def splat(@[LogAs(items(:id))] *orders : ItemOrder) : Nil
  end

  @[Logged]
  def double(@[LogAs(items(:id))] **orders : ItemOrder) : Nil
  end

  @[Logged]
  def masked(@[LogAs(items(:id), converter: ->(orders : Array(ItemOrder)) { orders.first(1) })] orders : Array(ItemOrder)) : Nil
  end

  @[Logged]
  def shout(@[LogAs(items(length: 4, converter: ->(note : String) { note.upcase }))] notes : Array(String)) : Nil
  end

  @[Logged]
  def untyped(@[LogAs(items(:id))] orders) : Nil
  end
end

private def order_full(id : String) : Log::Metadata::Value
  Log::Metadata::Value.new({"id" => Log::Metadata::Value.new(id), "total" => Log::Metadata::Value.new(1), "tags" => Log::Metadata::Value.new([Log::Metadata::Value.new("t")])})
end

private def texts(value : Log::Metadata::Value) : Array(String)
  value.as_a.map(&.as_s)
end

describe ItemFields do
  test "items(...) logs the items of an array at its detail, whatever the collection's" do
    assert texts(Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["orders"]) == ["o-1", "o-2"]
    assert texts(Logbuch.convert(ItemCustomer.new, detail: :full).as_h["orders"]) == ["o-1", "o-2"]
  end

  test "the detail of the items passes down into nested collections" do
    batches = Logbuch.convert(ItemCustomer.new, detail: :full).as_h["batches"]
    assert batches.as_a.map { |batch| texts(batch) } == [["o-1"], ["o-2"]]
  end

  test "items(...) logs the values of a hash and a named tuple, and the elements of a tuple and a set" do
    customer = Logbuch.convert(ItemCustomer.new, detail: :summary).as_h
    assert customer["by_code"].as_a.map(&.as_a.map(&.as_s)) == [["a", "o-1"]]
    assert texts(customer["pair"]) == ["o-1", "o-2"]
    assert customer["named"].as_h == {"first" => Log::Metadata::Value.new("o-1")}
    assert texts(customer["unique"]) == ["o-1"]
  end

  test "items(...) takes a Logbuch::Detail member" do
    assert texts(Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["by_path"]) == ["o-1"]
  end

  test "length: in items(...) cuts each item, and cap: next to it the collection" do
    notes = Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["notes"]
    assert texts(notes) == ["abc… (+3 bytes)", "ghi… (+3 bytes)", "… 1 more"]
  end

  test "cap: in items(...) limits each item that is a collection" do
    grid = Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["grid"]
    assert grid.as_a.map(&.as_a.map(&.to_s)) == [["1", "… 1 more"], ["3", "… 1 more"]]
  end

  test "converter: in items(...) converts each item" do
    shouted = Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["shouted"]
    assert shouted.as_a.map(&.as_a.map(&.as_s)) == [["a", "QUIET"], ["b", "CALM"]]
  end

  test "the converter of the collection runs first, and items(...) applies to what it returns" do
    assert texts(Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["converted"]) == ["o-1"]
  end

  test "a converter that raises shows a placeholder, for the one item or for the whole value" do
    customer = Logbuch.convert(ItemCustomer.new, detail: :summary).as_h
    assert texts(customer["failing"]) == ["", "#<convert raised ItemConvertError>"]
    assert customer["failing_whole"].as_s == "#<convert raised ItemConvertError>"
  end

  test "items(...) on a field that may be nil logs nil as nil" do
    assert Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["maybe"].raw.nil?
  end

  test "items(...) has no effect inside an identity, and holds where the field is logged as a field" do
    identity = Logbuch.convert(ItemCustomer.new, detail: :id).as_h
    assert identity["name"].as_s == "ann"
    assert texts(identity["codes"]) == ["abc"]
    assert texts(Logbuch.convert(ItemCustomer.new, detail: :summary).as_h["codes"]) == ["a… (+2 bytes)"]
  end
end

{% unless %w[off 0].includes?(flag?(:logbuch)) %}
  describe ItemParameters do
    test "items(...) on a parameter can be higher than the method's detail" do
      entries = capture_log { ItemShop.new.ship([ItemOrder.new("o-1")]) }
      assert entries[0].data[:args].as_h["orders"].as_a == [order_full("o-1")]
    end

    test "items(...) on a parameter can be lower than the method's detail, next to cap:" do
      entries = capture_log { ItemShop.new.list([ItemOrder.new("o-1"), ItemOrder.new("o-2")]) }
      assert texts(entries[0].data[:args].as_h["orders"]) == ["o-1", "… 1 more"]
    end

    test "items(...) logs the values of a hash parameter, not its keys" do
      entries = capture_log { ItemShop.new.index({"a" => ItemOrder.new("o-1")}) }
      assert entries[0].data[:args].as_h["by_code"].as_a.map(&.as_a.map(&.as_s)) == [["a", "o-1"]]
    end

    test "items(...) logs the elements of a splat and a double splat" do
      entries = capture_log { ItemShop.new.splat(ItemOrder.new("o-1"), ItemOrder.new("o-2")) }
      assert texts(entries[0].data[:args].as_h["orders"]) == ["o-1", "o-2"]
      entries = capture_log { ItemShop.new.double(a: ItemOrder.new("o-1")) }
      assert entries[0].data[:args].as_h["orders"].as_h == {"a" => Log::Metadata::Value.new("o-1")}
    end

    test "items(...) on a parameter applies to what its converter returns" do
      entries = capture_log { ItemShop.new.masked([ItemOrder.new("o-1"), ItemOrder.new("o-2")]) }
      assert texts(entries[0].data[:args].as_h["orders"]) == ["o-1"]
    end

    test "items(...) on a parameter converts and cuts each item" do
      entries = capture_log { ItemShop.new.shout(["quiet", "calm"]) }
      assert texts(entries[0].data[:args].as_h["notes"]) == ["QUIE… (+1 bytes)", "CALM"]
    end

    test "items(...) on a parameter without a type applies to a collection and leaves any other value" do
      entries = capture_log { ItemShop.new.untyped([ItemOrder.new("o-1")]) }
      assert texts(entries[0].data[:args].as_h["orders"]) == ["o-1"]
      entries = capture_log { ItemShop.new.untyped("abc") }
      assert entries[0].data[:args].as_h["orders"].as_s == "abc"
    end
  end
{% end %}

describe ItemChecks do
  test "items(...) takes one detail, :id, :summary or :full" do
    assert compile_error("items_bad_detail").to_s.includes?("logbuch: items(...) takes :id, :summary or :full, or a Logbuch::Detail member such as Logbuch::Detail::Full, not :bogus, on parameter orders of Offender#go")
    assert compile_error("items_omit_detail").to_s.includes?("logbuch: items(...) takes :id, :summary or :full, or a Logbuch::Detail member such as Logbuch::Detail::Full, not :omit, on field Offender@orders")
    assert compile_error("items_redacted_detail").to_s.includes?("logbuch: items(...) takes :id, :summary or :full, or a Logbuch::Detail member such as Logbuch::Detail::Full, not :redacted, on parameter orders of Offender#go")
    assert compile_error("items_two_details").to_s.includes?("logbuch: items(...) takes one detail at most, on parameter orders of Offender#go")
  end

  test "items(...) takes cap:, length: and converter:, and sets something" do
    assert compile_error("items_empty").to_s.includes?("logbuch: items() sets nothing on field Offender@orders; give it a detail, cap:, length: or converter:")
    assert compile_error("items_unknown_option").to_s.includes?("logbuch: unknown option depth in items(...) on parameter orders of Offender#go; use cap:, length: or converter:")
    assert compile_error("items_bad_converter").to_s.includes?("logbuch: converter: in items(...) takes a block in arrow notation with one parameter, such as ->(value) { value.upcase }, on parameter orders of Offender#go")
    assert compile_error("items_limit_not_a_number").to_s.includes?("logbuch: length: in items(...) takes a non-negative integer, on field Offender@names")
  end

  test "items(...) goes once, and not next to :omit or :redacted" do
    assert compile_error("items_twice").to_s.includes?("logbuch: @[LogAs] takes one detail, and :redacted and items(...) at most once, on field Offender@orders")
    assert compile_error("items_on_omit").to_s.includes?("logbuch: items(...) has no effect on :omit, on field Offender@orders")
    assert compile_error("items_on_redacted").to_s.includes?("logbuch: items(...) has no effect on :redacted, which logs \"***\", on parameter orders of Offender#go")
  end

  test "items(...) fails on a value that is not a collection" do
    assert compile_error("items_on_object").to_s.includes?("logbuch: items(...) has no effect on Loose, which is not an array, deque, set, slice, hash, tuple or named tuple: it sets how the items of a collection are logged, on parameter loose of Offender#go")
    assert compile_error("items_on_string_field").to_s.includes?("logbuch: items(...) has no effect on String, which is not an array, deque, set, slice, hash, tuple or named tuple: it sets how the items of a collection are logged, on field Offender@name")
  end

  test "the limits in items(...) are checked against the type of the items" do
    assert compile_error("items_length_on_number").to_s.includes?("logbuch: length: in items(...) has no effect on Int32: it cuts a string or inspect text only, on parameter counts of Offender#go")
    assert compile_error("items_cap_on_string").to_s.includes?("logbuch: cap: in items(...) has no effect on String, which is not an array, deque, set, slice or hash: it limits the items of a collection only, on field Offender@names")
  end

  test "items: and depth: are no options of @[LogAs]" do
    assert compile_error("option_items").to_s.includes?("logbuch: unknown option items on parameter orders of Offender#go; use cap: to limit the items of a collection, or items(...) to set how each item is logged")
    assert compile_error("option_depth").to_s.includes?("logbuch: unknown option depth on field Offender@orders; use converter:, cap: or length:, or items(...)")
  end
end
