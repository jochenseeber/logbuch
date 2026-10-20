require "../spec_helper"
require "../../src/logbuch"

class Lookup
  include Logbuch::Annotations

  @[Logged("looking up a key")]
  @[LogAccept(KeyError)]
  def find(key : String) : String
    {"a" => "1"}[key]
  end

  @[Logged]
  @[LogAccept(KeyError)]
  def parse(text : String) : Int32
    text.to_i
  end

  @[Logged]
  @[LogAccept(KeyError, IO::Error)]
  def read : Nil
    raise IO::TimeoutError.new("slow")
  end

  @[Logged(:omit)]
  @[LogAccept(KeyError)]
  def quiet : Int32
    raise KeyError.new("gone")
  end

  @[Logged]
  @[LogAccept(KeyError)]
  def each_key(&) : Nil
    yield "a"
    raise KeyError.new("b")
  end
end

# Calls the block and returns the exception it raises, or nil.
def raised(&) : Exception?
  yield
  nil
rescue error
  error
end

describe AllowedExceptions do
  test "an allowed exception is logged as the result and still raised" do
    error = nil
    entries = capture_log { error = raised { Lookup.new.find("b") } }
    assert error.is_a?(KeyError)
    assert entries.size == 2
    assert entries[1].message == "done looking up a key"
    assert entries[1].data[:result].as_h["type"].as_s == "KeyError"
    assert entries[1].data[:error]?.nil?
  end

  test "any other exception is logged as an error" do
    error = nil
    entries = capture_log { error = raised { Lookup.new.parse("x") } }
    assert error.is_a?(ArgumentError)
    assert entries[1].message == "!Lookup#parse"
    assert entries[1].data[:error].as_h["type"].as_s == "ArgumentError"
    assert entries[1].data[:result]?.nil?
  end

  test "a subclass of an allowed exception is allowed, also in a Nil method" do
    entries = capture_log { raised { Lookup.new.read } }
    assert entries[1].message == "<Lookup#read"
    assert entries[1].data[:result].as_h["type"].as_s == "IO::TimeoutError"
  end

  test "an allowed exception is logged as the result even with detail omit" do
    entries = capture_log { raised { Lookup.new.quiet } }
    assert entries[1].data[:result].as_h["message"].as_s == "gone"
  end

  test "an allowed exception in a yielding method writes one exit line" do
    keys = [] of String
    entries = capture_log { raised { Lookup.new.each_key { |key| keys << key } } }
    assert keys == ["a"]
    assert entries.size == 2
    assert entries[1].data[:result].as_h["type"].as_s == "KeyError"
  end

  test "LogAccept takes exception types, at least one" do
    message = "logbuch: @[LogAccept] takes exception types and one level, such as @[LogAccept(IO::Error, KeyError, :warn)], not "
    assert compile_error("log_accept_not_a_type").to_s.includes?(message + %("KeyError", on Offender#go))
    assert compile_error("log_accept_not_an_exception").to_s.includes?(message + "String, on Offender#go")
    assert compile_error("log_accept_without_types").to_s.includes?("logbuch: @[LogAccept] takes at least one exception type, on Offender#go")
  end
end
