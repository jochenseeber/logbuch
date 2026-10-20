require "../spec_helper"
require "../support/samples"

class Sample
  include Logbuch::Annotations

  @[Logged]
  def early(x : Int32) : String
    return "neg" if x < 0
    "pos"
  end

  @[Logged]
  def nothing(x : Int32) : Nil
  end

  @[Logged]
  def boom(x : Int32) : Int32
    raise Exception.new("boom", cause: KeyError.new("inner"))
  end

  @[Logged(:full, :debug)]
  def debug(card : Card) : Int32
    1
  end

  @[Logged(:id)]
  def ident(card : Card) : Int32
    1
  end

  @[Logged(:omit)]
  def hidden(x : String) : String
    x
  end

  @[Logged]
  def label : String # hand-written getter: traced, not a field marker
    "l"
  end

  @[Logged]
  def global_nil(x : Int32) : ::Nil
  end

  # Ameba discourages `Void` outside a lib, but Crystal accepts it.
  @[Logged]
  def void_result(x : Int32) : Void # ameba:disable Lint/VoidOutsideLib
  end

  @[Logged(:full)]
  def take(value : Explosive) : Int32
    1
  end

  @[Logged(Logbuch::Detail::Id)]
  def ident_path(card : Card) : Int32
    1
  end

  @[Logged]
  def boom : Nil
    raise ArgumentError.new("bad")
  end
end

module Shop
  Log = ::Log.for("shop")

  class Quiet
    include Logbuch::Annotations

    @[Logged(::Log::Severity::Debug)]
    def go : Int32
      1
    end

    @[Logged]
    def take(count : Int32) : Int32
      count
    end
  end
end

class Explosive
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    raise ArgumentError.new("boom")
  end
end

class Silent
  include Logbuch::Annotations

  @[Logged]
  def go : Int32
    1
  end
end

class Described
  include Logbuch::Annotations

  @[Logged("fooing the bar")]
  def foo(bar : Int32) : Int32
    bar
  end

  @[Logged("calling the API")]
  def api : Int32
    1
  end

  @[Logged("breaking the bar")]
  def broken : Int32
    raise ArgumentError.new("bad")
  end
end

describe TracingCore do
  test "the lines carry the keys Logbuch::Keys names" do
    timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
    entries = capture_log { Sample.new.early(1) }
    assert entries[0].data.map(&.first) == [Logbuch::Keys::METHOD, Logbuch::Keys::ARGS]
    assert entries[1].data.map(&.first) == (timing_off ? [Logbuch::Keys::METHOD, Logbuch::Keys::RESULT] : [Logbuch::Keys::METHOD, Logbuch::Keys::RESULT, Logbuch::Keys::DURATION])
    entries = capture_log { Sample.new.boom(1) rescue nil }
    assert entries[1].data.map(&.first) == (timing_off ? [Logbuch::Keys::METHOD, Logbuch::Keys::ERROR] : [Logbuch::Keys::METHOD, Logbuch::Keys::ERROR, Logbuch::Keys::DURATION])
    assert entries[1].data[Logbuch::Keys::ERROR].as_h.keys == [Logbuch::Keys::TYPE, Logbuch::Keys::MESSAGE, Logbuch::Keys::CAUSE]
  end

  test "return in the body still logs the exit" do
    entries = capture_log { Sample.new.early(-1) }
    assert entries.map(&.message) == [">Sample#early", "<Sample#early"]
    assert entries[0].data[:args].as_h["x"].as_i == -1
    assert entries[1].data[:result].as_s == "neg"
  end

  test "nil return type logs no result" do
    entries = capture_log { Sample.new.nothing(1) }
    assert entries[1].data[:result]?.nil?
  end

  test "level option sets the severity" do
    entries = capture_log { Sample.new.debug(Card.new) }
    assert entries.all?(&.severity.debug?)
    assert entries[0].data[:args].as_h["card"].as_h.has_key?("tags")
  end

  test "id method logs the identity, which shows only the id fields" do
    entries = capture_log { Sample.new.ident(Card.new) }
    assert entries[0].data[:args].as_h["card"].as_s == "c1"
  end

  test "an annotated hand-written getter is traced" do
    assert capture_log { Sample.new.label }.map(&.message) == [">Sample#label", "<Sample#label"]
  end

  test "omit method logs calls without data" do
    entries = capture_log { Sample.new.hidden("secret") }
    assert entries.size == 2
    assert entries[0].data[:args]?.nil?
    assert entries[1].data[:result]?.nil?
  end

  test "exceptions are logged once and re-raised unchanged" do
    error = nil
    entries = capture_log do
      Sample.new.boom
    rescue ex : ArgumentError
      error = ex
    end
    assert error.try(&.message) == "bad"
    assert entries.map(&.message) == [">Sample#boom", "!Sample#boom"]
    assert entries[1].data[:error].as_h["type"].as_s == "ArgumentError"
  end

  test "arguments are logged in a type whose module defines Log" do
    entries = capture_log { Shop::Quiet.new.take(3) }
    assert entries[0].data[:args].as_h["count"].as_i == 3
    assert entries.all? { |entry| entry.source == "shop" }
  end

  test "enclosing module log is used" do
    entries = capture_log { Shop::Quiet.new.go }
    assert entries.all? { |entry| entry.source == "shop" }
  end

  test "nothing is logged when the level is disabled" do
    log = Shop::Log
    log.level = :info
    entries = capture_log { Shop::Quiet.new.go }
    log.level = :trace
    assert entries.empty?
  end

  test "a disabled level allocates nothing per call" do
    log = ::Log.for("silent")
    log.level = :none
    silent = Silent.new
    silent.go
    # The count is for the whole process, so it takes the least of three runs,
    # in case something else allocates during one.
    allocated = Array.new(3) do
      before = GC.stats.total_bytes
      1000.times { silent.go }
      GC.stats.total_bytes - before
    end.min
    log.level = :trace
    assert allocated < 1024
  end

  test "a global nil return type logs no result" do
    entries = capture_log { Sample.new.global_nil(1) }
    assert entries[1].data[:result]?.nil?
  end

  test "a Void return type logs no result" do
    entries = capture_log { Sample.new.void_result(1) }
    assert entries.size == 2
    assert entries[1].data[:result]?.nil?
  end

  test "a raising to_trace does not stop the call" do
    entries = capture_log { assert Sample.new.take(Explosive.new) == 1 }
    assert entries[0].data[:args].as_h["value"].as_s == "#<to_trace raised ArgumentError>"
    assert entries[1].message == "<Sample#take"
  end

  test "the trace log is not part of the type's API" do
    assert compile_error("private_log").to_s.includes?("private constant")
    assert compile_error("log_method").to_s.includes?("undefined method '__logbuch_log'")
  end

  test "unknown options, moved options and repeated arguments fail to compile" do
    assert compile_error("unknown_option").to_s.includes?("logbuch: unknown option verbose on Offender#go; use lock:, log:, result:, slow: or timing:")
    assert compile_error("moved_option").to_s.includes?("logbuch: allow: is not an option of @[Logged]; use @[LogAccept(...)] on Offender#go")
    assert compile_error("two_levels").to_s.includes?("logbuch: @[Logged] takes one level, on Offender#go")
    assert compile_error("two_descriptions").to_s.includes?("logbuch: @[Logged] takes one description, on Offender#go")
  end

  test "other annotations stay on the traced method" do
    success, output = compile_output("compile_warnings/deprecated_call")
    assert success
    assert output.includes?("deprecated_call.cr:14")
    assert output.includes?("Deprecated Offender#old. use other")
  end

  test "a description becomes the message" do
    entries = capture_log { Described.new.foo(1) }
    assert entries.map(&.message) == ["fooing the bar", "done fooing the bar"]
    assert entries.all? { |entry| entry.data[:method].as_s == "Described#foo" }
    assert entries[0].data[:args].as_h["bar"].as_i == 1
  end

  test "a description is used as written, without capitalization" do
    entries = capture_log { Described.new.api }
    assert entries.map(&.message) == ["calling the API", "done calling the API"]
    assert entries[0].data[:args]?.nil?
  end

  test "an error uses the description" do
    entries = capture_log do
      Described.new.broken
    rescue ArgumentError
    end
    assert entries.map(&.message) == ["breaking the bar", "error breaking the bar"]
    assert entries[1].data[:method].as_s == "Described#broken"
  end

  test "without a description the method name is the message" do
    entries = capture_log { Sample.new.early(1) }
    assert entries.map(&.message) == [">Sample#early", "<Sample#early"]
    assert entries.all? { |entry| entry.data[:method].as_s == "Sample#early" }
  end

  test "detail accepts a Logbuch::Detail value" do
    entries = capture_log { Sample.new.ident_path(Card.new) }
    assert entries[0].data[:args].as_h["card"].as_s == "c1"
  end

  test "LogAs on methods and invalid details fail to compile" do
    assert compile_error("invalid_detail").to_s.includes?("logbuch: @[Logged] takes a description string, a level (:trace, :debug, :info, :notice, :warn, :error or :fatal) and a detail (:omit, :id, :summary or :full), not :everything, on Offender#go")
    assert compile_error("detail_on_method").to_s.includes?("logbuch: @[LogAs] goes on parameters and fields; trace Offender#go with @[Logged] and give it the detail, such as @[Logged(:full)]")
  end

  test ":redacted on a method fails to compile and names where it goes" do
    assert compile_error("logged_redacted").to_s.includes?("logbuch: :redacted goes on parameters and fields with @[LogAs(:redacted)], not on Offender#go")
  end

  test "an empty description fails to compile" do
    assert compile_error("empty_description").to_s.includes?(%(logbuch: @[Logged] takes a description string, a level (:trace, :debug, :info, :notice, :warn, :error or :fatal) and a detail (:omit, :id, :summary or :full), not "", on Offender#go))
  end

  test "default source is the type name" do
    assert capture_log { Sample.new.label }.all? { |entry| entry.source == "sample" }
  end

  test "invalid level and two method annotations fail to compile" do
    assert compile_error("invalid_level").to_s.includes?("logbuch: @[Logged] takes a description string, a level (:trace, :debug, :info, :notice, :warn, :error or :fatal) and a detail (:omit, :id, :summary or :full), not :verbose, on Offender#go")
    assert compile_error("two_method_annotations").to_s.includes?("logbuch: Offender#go has more than one @[Logged]")
  end

  test "methods the wrapper cannot forward fail to compile with a clear message" do
    assert compile_error("with_yield").to_s.includes?("logbuch: Offender#build uses `with … yield`, which a traced method cannot forward")
    assert compile_error("with_yield_after_literals").to_s.includes?("logbuch: Offender#build uses `with … yield`, which a traced method cannot forward")
    success, output = compile_output("compiles/with_yield_in_string")
    puts output unless success
    assert success
    assert compile_error("trace_initialize").to_s.includes?("logbuch: cannot trace Offender#initialize")
    assert compile_error("splat_then_required_named").to_s.includes?("logbuch: cannot trace Offender#go: Crystal adds a redefinition of a method whose typed splat *rest is followed by the required named parameter key as an overload instead of replacing the method")
  end

  test "detail and level paths must name logbuch's and the stdlib's own values" do
    assert compile_error("invalid_detail_path").to_s.includes?("logbuch: @[Logged] takes a description string, a level (:trace, :debug, :info, :notice, :warn, :error or :fatal) and a detail (:omit, :id, :summary or :full), not Bogus::Full, on Offender#go")
    assert compile_error("invalid_level_path").to_s.includes?("logbuch: @[Logged] takes a description string, a level (:trace, :debug, :info, :notice, :warn, :error or :fatal) and a detail (:omit, :id, :summary or :full), not Bogus::Debug, on Offender#go")
  end

  test "annotations are checked with -Dlogbuch=off too" do
    assert compile_error("invalid_detail", flags: ["logbuch=off"]).to_s.includes?("logbuch: @[Logged] takes a description string, a level (:trace, :debug, :info, :notice, :warn, :error or :fatal) and a detail (:omit, :id, :summary or :full), not :everything, on Offender#go")
    assert compile_error("splat_then_required_named", flags: ["logbuch=off"]).to_s.includes?("logbuch: cannot trace Offender#go")
    assert compile_error("param_options", flags: ["logbuch=off"]).to_s.includes?("logbuch: level: and timing: are only allowed on methods")
    assert compile_error("length_on_collection", flags: ["logbuch=off"]).to_s.includes?("logbuch: length: has no effect on Array(String)")
  end
end
