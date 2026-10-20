require "../spec_helper"
require "../../src/logbuch"

class Courier
  include Logbuch::Annotations

  @[Logged(slow: {ms: 50, level: :error})]
  def wait(ms : Int32) : Int32
    sleep ms.milliseconds
    ms
  end

  @[Logged(slow: {ms: 50, level: ::Log::Severity::Error})]
  def wait_path(ms : Int32) : Int32
    sleep ms.milliseconds
    ms
  end

  @[Logged(slow: {ms: 49.5, level: :error})]
  def wait_fraction(ms : Int32) : Int32
    sleep ms.milliseconds
    ms
  end

  @[Logged(slow: {ms: 50})]
  def wait_quietly(ms : Int32) : Int32
    sleep ms.milliseconds
    ms
  end

  @[Logged(slow: {ms: 50, level: :error})]
  def fail_fast(code : Int32) : Int32
    raise ArgumentError.new("failed #{code}")
  end

  @[Logged(slow: {ms: 50, level: :error})]
  @[LogAccept(KeyError)]
  def wait_then_miss(ms : Int32) : Int32
    sleep ms.milliseconds
    raise KeyError.new("gone")
  end

  @[Logged(slow: {ms: 50, args: true})]
  def fill(items : Array(Int32), ms : Int32) : Nil
    sleep ms.milliseconds
    items << ms
  end

  @[Logged(slow: {ms: 50, level: :error})]
  def each_tick(ms : Int32, &) : Nil
    sleep ms.milliseconds
    yield 1
    yield 2
  end

  # How often the converters of `counted` and `counted_with_args` ran.
  class_property conversions = 0

  @[Logged(slow: {ms: 50}, result: ->(ms) { Courier.conversions += 1; ms })]
  def counted(@[LogAs(:summary, converter: ->(ms) { Courier.conversions += 1; ms })] ms : Int32) : Int32
    sleep ms.milliseconds
    ms
  end

  @[Logged(slow: {ms: 50, args: true}, result: ->(ms) { Courier.conversions += 1; ms })]
  def counted_with_args(@[LogAs(:summary, converter: ->(ms) { Courier.conversions += 1; ms })] ms : Int32) : Int32
    sleep ms.milliseconds
    ms
  end
end

# Runs the block with the courier log at `:info`, so the `:trace` lines of
# `Courier` are disabled and only slow lines are written.
def at_info(&)
  log = ::Log.for("courier")
  log.level = :info
  Courier.conversions = 0
  yield
ensure
  ::Log.for("courier").level = :trace
end

{% unless %w[off 0].includes?(flag?(:logbuch)) %}
  describe SlowCalls do
    test "a fast call logs its entry and exit lines at the method's level" do
      entries = capture_log { assert Courier.new.wait(0) == 0 }
      assert entries.map(&.message) == [">Courier#wait", "<Courier#wait"]
      assert entries.all?(&.severity.trace?)
    end

    test "a slow call logs its exit line at slow:'s level" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      entries = capture_log { assert Courier.new.wait(60) == 60 }
      assert entries.map(&.message) == [">Courier#wait", "<Courier#wait"]
      assert entries[0].severity.trace?
      assert entries[0].data[:args].as_h["ms"].as_i == 60
      assert entries[1].data[:result].as_i == 60
      # With timing off, no call is known to be slow.
      assert entries[1].severity == (timing_off ? Log::Severity::Trace : Log::Severity::Error)
    end

    test "a slow call's exit line carries slow: true, and a fast one's no slow key" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      fast = capture_log { Courier.new.wait(0) }
      assert fast.all? { |entry| entry.data[:slow]?.nil? }
      slow = capture_log { Courier.new.wait(60) }
      assert slow[0].data[:slow]?.nil?
      assert slow[1].data[:slow]? == (timing_off ? nil : Log::Metadata::Value.new(true))
      assert slow[1].data.to_a.last[0] == Logbuch::Keys::SLOW unless timing_off
    end

    test "the exit line of a slow yielding call carries slow: true, also when its block breaks out" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      expected = timing_off ? nil : Log::Metadata::Value.new(true)
      assert capture_log { Courier.new.each_tick(60) { } }[1].data[:slow]? == expected
      assert capture_log { Courier.new.each_tick(60) { break } }[1].data[:slow]? == expected
      assert capture_log { Courier.new.each_tick(0) { break } }[1].data[:slow]?.nil?
    end

    test "the exit line of a slow call that ends in an accepted exception carries slow: true" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      entries = capture_log { Courier.new.wait_then_miss(60) rescue nil }
      assert entries[1].message == "<Courier#wait_then_miss"
      assert entries[1].data[:slow]? == (timing_off ? nil : Log::Metadata::Value.new(true))
      assert capture_log { Courier.new.wait_then_miss(0) rescue nil }[1].data[:slow]?.nil?
    end

    test "slow:'s level can be a Log::Severity path" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      entries = capture_log { Courier.new.wait_path(60) }
      assert entries[1].severity == (timing_off ? Log::Severity::Trace : Log::Severity::Error)
    end

    test "slow: takes a fractional ms" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      assert capture_log { Courier.new.wait_fraction(0) }[1].severity.trace?
      entries = capture_log { Courier.new.wait_fraction(60) }
      assert entries[1].severity == (timing_off ? Log::Severity::Trace : Log::Severity::Error)
    end

    test "slow: logs a slow call at warn by default" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      entries = capture_log { Courier.new.wait_quietly(60) }
      assert entries[1].severity == (timing_off ? Log::Severity::Trace : Log::Severity::Warn)
    end

    test "an error is logged at error" do
      entries = capture_log { Courier.new.fail_fast(7) rescue nil }
      assert entries.map(&.message) == [">Courier#fail_fast", "!Courier#fail_fast"]
      assert entries[1].severity.error?
    end

    test "a fast call converts nothing when only its slow lines are enabled" do
      at_info do
        entries = capture_log { assert Courier.new.counted(0) == 0 }
        assert entries.empty?
        assert Courier.conversions == 0
      end
    end

    test "a slow call whose entry line is disabled logs its exit line without arguments" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      at_info do
        entries = capture_log { Courier.new.counted(60) }
        if timing_off
          assert entries.empty?
        else
          assert entries.map(&.message) == ["<Courier#counted"]
          assert entries[0].severity.warn?
          assert entries[0].data[:args]?.nil?
          assert entries[0].data[:result].as_i == 60
          assert Courier.conversions == 1
        end
      end
    end

    test "slow: args: true adds the arguments to a slow exit line without an entry line" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      at_info do
        entries = capture_log { Courier.new.counted_with_args(60) }
        if timing_off
          assert entries.empty?
        else
          assert entries.map(&.message) == ["<Courier#counted_with_args"]
          assert entries[0].data[:args].as_h["ms"].as_i == 60
          assert entries[0].data[:result].as_i == 60
        end
      end
    end

    test "slow: args: true converts the arguments after the method returns" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      at_info do
        items = [1]
        entries = capture_log { Courier.new.fill(items, 60) }
        if timing_off
          assert entries.empty?
        else
          assert entries.map(&.message) == ["<Courier#fill"]
          assert entries[0].data[:args].as_h["items"].as_a.map(&.as_i) == [1, 60]
        end
      end
    end

    test "a call left by break gets the duration and slow:'s level on its exit line" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      fast = capture_log { assert Courier.new.each_tick(0) { |tick| break tick * 10 } == 10 }
      slow = capture_log { assert Courier.new.each_tick(60) { |tick| break tick * 10 } == 10 }
      assert fast.map(&.message) == [">Courier#each_tick", "<Courier#each_tick"]
      assert slow.map(&.message) == [">Courier#each_tick", "<Courier#each_tick"]
      assert fast[1].severity.trace?
      assert slow[1].data[:result]?.nil?
      if timing_off
        assert slow[1].severity.trace?
        assert slow[1].data[:duration_ns]?.nil?
      else
        assert slow[1].severity.error?
        assert slow[1].data[:duration_ns].as_u64 >= 60_000_000
      end
    end

    test "slow: args: true adds no arguments to the exit line when the entry line has them" do
      entries = capture_log { Courier.new.counted_with_args(60) }
      assert entries.map(&.message) == [">Courier#counted_with_args", "<Courier#counted_with_args"]
      assert entries[0].data[:args].as_h["ms"].as_i == 60
      assert entries[1].data[:args]?.nil?
    end

    test "bad slow: options fail to compile" do
      assert compile_error("slow_not_a_tuple").to_s.includes?("logbuch: slow: takes a named tuple such as {ms: 200, level: :warn}, on Offender#go")
      assert compile_error("slow_without_ms").to_s.includes?("logbuch: slow: takes a named tuple such as {ms: 200, level: :warn}, on Offender#go")
      assert compile_error("slow_bad_level").to_s.includes?("logbuch: invalid slow: level :loud on Offender#go")
      assert compile_error("slow_bad_level_path").to_s.includes?("logbuch: invalid slow: level ::Log::Severity::Loud on Offender#go")
      assert compile_error("slow_without_timing").to_s.includes?("logbuch: slow: needs timing, so it takes no timing: false, on Offender#go")
      assert compile_error("slow_args_not_bool").to_s.includes?("logbuch: slow: args: must be true or false on Offender#go")
      assert compile_error("slow_args_without_arguments").to_s.includes?("logbuch: slow: args: has no effect on Offender#go, which logs no arguments")
      assert compile_error("slow_level_not_above").to_s.includes?("logbuch: slow: level :warn must be above the method's level :error, on Offender#go")
    end

    test "the build flags take only their documented values" do
      success, output = compile_output("compiles/version", flags: ["logbuch=maybe"])
      assert !success
      assert output.includes?("logbuch: -Dlogbuch takes on, off, 1 or 0")
      success, output = compile_output("compiles/version", flags: ["logbuch_timing=slow"])
      assert !success
      assert output.includes?("logbuch: -Dlogbuch_timing takes on, off, 1 or 0")
      %w[0 1].each do |value|
        success, output = compile_output("compiles/version", flags: ["logbuch=#{value}", "logbuch_timing=#{value}"])
        puts output unless success
        assert success
      end
    end

    test "0 turns tracing off like off, and 1 leaves it on like on" do
      assert compile_error("tracing_probe").to_s.includes?("logbuch: tracing is on")
      assert compile_error("tracing_probe", flags: ["logbuch=1"]).to_s.includes?("logbuch: tracing is on")
      assert compile_error("tracing_probe", flags: ["logbuch=off"]).nil?
      assert compile_error("tracing_probe", flags: ["logbuch=0"]).nil?
    end
  end
{% end %}
