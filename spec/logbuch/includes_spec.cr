require "../spec_helper"
require "../../src/logbuch"

# A program opts in to the short names at its top level; the types below that
# use them include nothing themselves.
include Logbuch::Annotations

class Reopened
  include Logbuch::Annotations

  @[Logged]
  def go : Int32
    1
  end
end

class Reopened
  include Logbuch::Tracing
end

# Inherits the names and the hooks, so it needs no include of its own.
class ReopenedChild < Reopened
  @[Logged]
  def stay : Int32
    2
  end
end

module Greets
  include Logbuch::Annotations

  @[Logged]
  def greet(name : String) : String
    "hi #{name}"
  end

  @[Logged]
  def each_letter(&) : Nil
    yield 'h'
    yield 'i'
  end
end

# Includes a traced module, but not Logbuch::Tracing.
class PlainGreeter
  include Greets
end

class TracedGreeter
  include Logbuch::Annotations
  include Greets

  @[Logged]
  def wave : Int32
    1
  end
end

class OwnGreeter
  include Greets

  def greet(name : String) : String
    "hello #{name}"
  end
end

# None of these include anything; logbuch adds Logbuch::Tracing.
class AutoClass
  @[Logged]
  def go : Int32
    1
  end
end

struct AutoStruct
  @[Logged]
  def go : Int32
    2
  end
end

module AutoModule
  @[Logged]
  def self.go : Int32
    3
  end
end

class AutoCrate(T)
  @[Logged]
  def go : Int32
    4
  end
end

abstract class AutoBase
  abstract def kind : String

  @[Logged]
  def go : Int32
    5
  end
end

class AutoDerived < AutoBase
  def kind : String
    "derived"
  end

  @[Logged]
  def more : Int32
    6
  end
end

module AutoOuter
  class Inner
    @[Logged]
    def go : Int32
      7
    end
  end
end

class AutoGreeter
  include Greets

  @[Logged]
  def wave : Int32
    8
  end
end

# A private type includes the module like any other.
private class Hidden
  include Logbuch::Annotations

  @[Logged]
  def go : Int32
    9
  end
end

# A private top-level module is hidden from logbuch's end-of-build check, so it
# includes the module itself to be traced.
private module HiddenHelper
  include Logbuch::Annotations
  extend self

  @[Logged]
  def help : Int32
    10
  end
end

# A type defined in the program's own `macro finished` may come after logbuch's
# check, so it includes the module itself to be traced.
macro finished
  class LateTraced
    include Logbuch::Annotations

    @[Logged]
    def go : Int32
      11
    end
  end
end

module Helper
  include Logbuch::Annotations
  extend self

  @[Logged]
  def double(value : Int32) : Int32
    value * 2
  end

  @[Logged]
  def self.triple(value : Int32) : Int32
    value * 3
  end
end

describe IncludeRules do
  test "a second include in a reopened class traces once" do
    assert capture_log { Reopened.new.go }.size == 2
  end

  test "a subclass of a class included twice compiles and traces once" do
    assert capture_log { ReopenedChild.new.go }.size == 2
    assert capture_log { ReopenedChild.new.stay }.size == 2
  end
  test "a module method is traced in a class that does not include Logbuch::Tracing" do
    entries = capture_log { assert PlainGreeter.new.greet("ada") == "hi ada" }
    assert entries.size == 2
    assert entries[0].data[:method].as_s == "Greets#greet"
    assert entries[0].data[:args].as_h["name"].as_s == "ada"
  end

  test "a module method is traced once in a class that includes Logbuch::Tracing too" do
    assert capture_log { TracedGreeter.new.greet("ada") }.size == 2
    assert capture_log { TracedGreeter.new.wave }.size == 2
  end

  test "a traced module method that yields forwards the block" do
    letters = [] of Char
    entries = capture_log { PlainGreeter.new.each_letter { |letter| letters << letter } }
    assert letters == ['h', 'i']
    assert entries.size == 2
  end

  test "a method the class defines itself replaces the module's" do
    entries = capture_log { assert OwnGreeter.new.greet("ada") == "hello ada" }
    assert entries.empty?
  end

  test "module methods called on the module are traced" do
    entries = capture_log do
      assert Helper.double(2) == 4
      assert Helper.triple(2) == 6
    end
    assert entries.map(&.data[:method].as_s) == ["Helper#double", "Helper#double", "Helper.triple", "Helper.triple"]
  end

  test "a class, struct, module, generic or nested type is traced without an include" do
    entries = capture_log do
      assert AutoClass.new.go == 1
      assert AutoStruct.new.go == 2
      assert AutoModule.go == 3
      assert AutoCrate(String).new.go == 4
      assert AutoOuter::Inner.new.go == 7
    end
    assert entries.map(&.data[:method].as_s) == [
      "AutoClass#go", "AutoClass#go", "AutoStruct#go", "AutoStruct#go", "AutoModule.go", "AutoModule.go",
      "AutoCrate#go", "AutoCrate#go", "AutoOuter::Inner#go", "AutoOuter::Inner#go",
    ]
  end

  test "an abstract parent and its subclass are each traced once, the subclass without an include" do
    entries = capture_log do
      assert AutoDerived.new.go == 5
      assert AutoDerived.new.more == 6
    end
    assert entries.map(&.data[:method].as_s) == ["AutoBase#go", "AutoBase#go", "AutoDerived#more", "AutoDerived#more"]
  end

  test "a class that includes a traced module gets its own methods traced too" do
    entries = capture_log do
      AutoGreeter.new.wave
      AutoGreeter.new.greet("ada")
    end
    assert entries.map(&.data[:method].as_s) == ["AutoGreeter#wave", "AutoGreeter#wave", "Greets#greet", "Greets#greet"]
  end

  test "a private type that includes Logbuch::Annotations is traced" do
    assert capture_log { assert Hidden.new.go == 9 }.size == 2
  end

  test "a traced method in a private type without an include fails to compile" do
    assert compile_error("forgot_include_private").to_s.includes?("logbuch: Forgetful#go is traced, but logbuch cannot include Logbuch::Tracing into the private type Forgetful; add `include Logbuch::Annotations` to Forgetful")
  end

  test "a traced method in a class inside a private module without an include fails to compile" do
    assert compile_error("forgot_include_in_private").to_s.includes?("logbuch: Workshop::Bench#go is traced, but logbuch cannot include Logbuch::Tracing into Workshop::Bench, which is inside a private type; add `include Logbuch::Annotations` to Workshop::Bench")
  end

  test "a private top-level module that includes Logbuch::Annotations is traced" do
    entries = capture_log { assert HiddenHelper.help == 10 }
    assert entries.map(&.data[:method].as_s) == ["HiddenHelper#help", "HiddenHelper#help"]
  end

  test "a type defined in a macro finished that includes Logbuch::Annotations is traced" do
    entries = capture_log { assert LateTraced.new.go == 11 }
    assert entries.map(&.data[:method].as_s) == ["LateTraced#go", "LateTraced#go"]
  end

  test "a traced method of an enum fails to compile" do
    assert compile_error("enum_method").to_s.includes?("logbuch: Color#shout is traced, but Crystal lets no enum include a module, so logbuch cannot trace the methods of the enum Color; trace a method of a class, struct or module instead")
  end

  test "a traced class method of a nested enum fails to compile" do
    assert compile_error("enum_class_method").to_s.includes?("logbuch: Palette::Shade.pick is traced, but Crystal lets no enum include a module, so logbuch cannot trace the methods of the enum Palette::Shade; trace a method of a class, struct or module instead")
  end

  test "without the top-level include, a program's own Logged and LogError and the full names work side by side" do
    output = run_program("full_names", args: [] of String)
    assert output.lines == [
      "the program's Logged",
      %(TRACE >PaymentShard::Client#charge {"card" => "***"}),
      "WARN !PaymentShard::Client#charge IO::Error",
      "TRACE >Shop#place ",
      "ERROR !Shop#place LogError",
    ]
  end

  test "a program's own Logged hides the annotation, which it writes by its full name or an alias" do
    output = run_program("own_names", args: [] of String)
    assert output.lines == [
      "the program's Logged", "MyApp's Logged",
      ">Shop#place", ">Shop#cancel", ">MyApp::Order#ship", ">Plain#go",
    ]
  end

  test "an application module named Logbuch does not confuse the shard" do
    success, output = compile_output("compiles/shadowed_logbuch")
    puts output unless success
    assert success
  end
end
