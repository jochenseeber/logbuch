require "../spec_helper"
require "../../src/logbuch"

class Kinds
  include Logbuch::Annotations

  @[Logged]
  def self.klass(text : String) : String
    text.upcase
  end

  @[Logged]
  def splats(a, *rest, k = 1, **opts)
    {a, rest, k, opts}
  end

  # Crystal replaces these when they are redefined, unlike a typed splat
  # followed by a named parameter without a default, which fails to compile.
  @[Logged]
  def typed_splat(*rest : Int32, k : Int32 = 1) : Int32
    rest.sum + k
  end

  @[Logged]
  def untyped_splat(*rest, key)
    {rest, key}
  end

  @[Logged]
  def find(for value : String) : String
    value
  end

  @[Logged]
  def pairs(&)
    yield 0, 0
    yield 1, 2
    nil
  end

  @[Logged]
  def with_block(&block : Int32 -> Int32) : Int32
    block.call(3)
  end

  @[Logged]
  def over(a : Int32) : String
    "int"
  end

  @[Logged]
  def over(a : String) : String
    "string"
  end

  @[Logged]
  def generic(x : T) : T forall T
    x
  end

  @[Logged]
  def defaults(a : Int32, b : Int32 = a * 2) : Int32
    a + b
  end

  @[Logged]
  def clash(__logbuch_result : Int32, __logbuch_log : Int32, __logbuch_started : Int32) : Int32
    __logbuch_result + __logbuch_log + __logbuch_started
  end

  # Returns from inside the block it passes to the traced `pairs`.
  def self.first_pair : Int32
    Kinds.new.pairs { |a, _| return a + 100 }
    -1
  end

  def call_hidden : Int32
    secret + guarded
  end

  @[Logged]
  private def secret : Int32
    1
  end

  @[Logged]
  protected def guarded : Int32
    2
  end
end

class Parent
  include Logbuch::Annotations

  @[Logged]
  def parent_only : Int32
    1
  end
end

class Child < Parent
  include Logbuch::Annotations

  @[Logged]
  def child_only : Int32
    2
  end
end

class GrandChild < Child
  include Logbuch::Annotations

  @[Logged]
  def grand_only : Int32
    3
  end
end

module Elsewhere
  Log = ::Log.for("elsewhere")

  class Borrower < Parent
    include Logbuch::Annotations

    @[Logged]
    def borrow : Int32
      5
    end
  end
end

class OwnLog < Parent
  include Logbuch::Annotations

  Log = ::Log.for("own")

  @[Logged]
  def own : Int32
    6
  end
end

class Both < Parent
  include Logbuch::Annotations

  @[Logged]
  def both : Int32
    4
  end
end

class Crate(T)
  include Logbuch::Annotations

  def initialize(@value : T)
  end

  @[Logged]
  def get : T
    @value
  end
end

struct Point
  include Logbuch::Annotations

  @[Logged]
  def x : Int32
    1
  end
end

class Ops
  include Logbuch::Annotations

  @[Logged]
  def [](index : Int32) : Int32
    index
  end

  @[Logged]
  def ==(other : Ops) : Bool
    true
  end

  @[Logged]
  def name=(value : String) : String
    value
  end

  @[Logged]
  def valid? : Bool
    true
  end
end

# Its own `Tuple` and `NamedTuple` hide the stdlib ones from the wrappers.
class Shadowed
  include Logbuch::Annotations

  class Tuple
  end

  class NamedTuple
  end

  @[Logged(timing: false)]
  def ping : Nil
  end

  @[Logged(timing: false)]
  def each_one(&) : Nil
    yield 1
  end
end

describe MethodKinds do
  test "class method" do
    entries = capture_log { assert Kinds.klass("hi") == "HI" }
    assert entries.map(&.message) == [">Kinds.klass", "<Kinds.klass"]
  end

  test "splats, double splats and named-only parameters are forwarded and logged" do
    entries = capture_log { assert Kinds.new.splats(1, 2, 3, k: 4, z: 5) == {1, {2, 3}, 4, {z: 5}} }
    args = entries[0].data[:args].as_h
    assert args["rest"].as_a.map(&.as_i) == [2, 3]
    assert args["opts"].as_h["z"].as_i == 5
    assert args["k"].as_i == 4
  end

  test "a typed splat with a defaulted named parameter, and an untyped splat with a required one, are traced" do
    entries = capture_log { assert Kinds.new.typed_splat(1, 2, k: 3) == 6 }
    assert entries.map(&.message) == [">Kinds#typed_splat", "<Kinds#typed_splat"]
    entries = capture_log { assert Kinds.new.untyped_splat(1, key: 2) == { {1}, 2 } }
    assert entries.map(&.message) == [">Kinds#untyped_splat", "<Kinds#untyped_splat"]
  end

  test "external parameter names" do
    entries = capture_log { assert Kinds.new.find(for: "x") == "x" }
    assert entries.map(&.message) == [">Kinds#find", "<Kinds#find"]
    assert entries[0].data[:args].as_h["value"].as_s == "x"
  end

  test "yield with several values, next and break" do
    collected = [] of Int32
    entries = capture_log do
      Kinds.new.pairs do |a, b|
        next if a == 0
        collected << a + b
      end
    end
    assert collected == [3]
    assert entries.map(&.message) == [">Kinds#pairs", "<Kinds#pairs"]
    result = Kinds.new.pairs { |a, _| break a * 10 }
    assert result == 0
  end

  test "break from the caller's block still logs the exit" do
    entries = capture_log { assert Kinds.new.pairs { |a, _| break a * 10 } == 0 }
    assert entries.map(&.message) == [">Kinds#pairs", "<Kinds#pairs"]
    assert entries[1].data[:result]?.nil?
  end

  test "return from the caller's block still logs the exit" do
    entries = capture_log { assert Kinds.first_pair == 100 }
    assert entries.map(&.message) == [">Kinds#pairs", "<Kinds#pairs"]
    assert entries[1].data[:result]?.nil?
  end

  test "parameters named like generated locals" do
    entries = capture_log { assert Kinds.new.clash(1, 2, 3) == 6 }
    assert entries.map(&.message) == [">Kinds#clash", "<Kinds#clash"]
  end

  test "captured block" do
    entries = capture_log { assert Kinds.new.with_block { |value| value + 1 } == 4 }
    assert entries.map(&.message) == [">Kinds#with_block", "<Kinds#with_block"]
  end

  test "overloads, generics and defaults" do
    entries = capture_log do
      assert Kinds.new.over(1) == "int"
      assert Kinds.new.over("s") == "string"
      assert Kinds.new.generic(:sym) == :sym
      assert Kinds.new.defaults(1) == 3
    end
    assert entries.map(&.message) == [">Kinds#over", "<Kinds#over", ">Kinds#over", "<Kinds#over",
                                      ">Kinds#generic", "<Kinds#generic", ">Kinds#defaults", "<Kinds#defaults"]
    assert entries[6].data[:args].as_h["b"].as_i == 2
  end

  test "private and protected methods keep their visibility and are traced" do
    messages = capture_log { Kinds.new.call_hidden }.map(&.message)
    assert messages.includes?(">Kinds#secret")
    assert messages.includes?(">Kinds#guarded")
    assert compile_error("private_call").to_s.includes?("Error: private method 'secret' called for Offender")
  end

  test "subclasses, grandchildren and double include trace once" do
    assert capture_log { Child.new.child_only }.size == 2
    assert capture_log { GrandChild.new.grand_only }.size == 2
    assert capture_log { Both.new.both }.size == 2
  end

  test "subclasses log to their own source" do
    assert capture_log { Elsewhere::Borrower.new.borrow }.all? { |entry| entry.source == "elsewhere" }
    assert capture_log { OwnLog.new.own }.all? { |entry| entry.source == "own" }
    assert capture_log { Child.new.child_only }.all? { |entry| entry.source == "child" }
  end

  test "generic type, struct and operator names" do
    assert capture_log { Crate(Int32).new(1).get }.map(&.message).first == ">Crate#get"
    assert capture_log { Point.new.x }.size == 2
    names = capture_log do
      ops = Ops.new
      ops[1]
      assert ops == Ops.new
      ops.name = "a"
      ops.valid?
    end.map(&.message)
    assert names.includes?(">Ops#[]")
    assert names.includes?(">Ops#==")
    assert names.includes?(">Ops#name=")
    assert names.includes?(">Ops#valid?")
  end

  test "a type with its own Tuple and NamedTuple is traced" do
    entries = capture_log do
      Shadowed.new.ping
      Shadowed.new.each_one { |value| break value }
    end
    assert entries.map(&.message) == [">Shadowed#ping", "<Shadowed#ping", ">Shadowed#each_one", "<Shadowed#each_one"]
    assert entries.none?(&.data[:duration_ns]?)
  end

  test "exception from the caller's block passes through once" do
    entries = capture_log do
      Kinds.new.pairs { raise KeyError.new("x") }
    rescue KeyError
    end
    assert entries.map(&.message) == [">Kinds#pairs", "!Kinds#pairs"]
  end

  test "abstract def fails to compile" do
    assert compile_error("abstract_def").to_s.includes?("trace the implementations instead")
  end
end
