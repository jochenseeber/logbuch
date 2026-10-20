require "../spec_helper"
require "../../src/logbuch"

# A result that takes a while to convert.
class SlowResult
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    sleep 50.milliseconds
    Log::Metadata::Value.new("slow")
  end
end

class Timed
  include Logbuch::Annotations

  @[Logged]
  def default : Int32
    1
  end

  @[Logged(timing: true)]
  def forced : Int32
    1
  end

  @[Logged(timing: false)]
  def disabled : Int32
    1
  end

  @[Logged(timing: true)]
  def slow_result : SlowResult
    SlowResult.new
  end

  @[Logged(timing: true)]
  def pausing : Nil
    sleep 2.milliseconds
  end

  @[Logged(timing: true)]
  def failing : Int32
    raise ArgumentError.new("bad")
  end
end

{% unless %w[off 0].includes?(flag?(:logbuch)) %}
  describe TimingTable do
    test "times every build unless timing: false or -Dlogbuch_timing=off" do
      no_timing = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      default = capture_log { Timed.new.default }[1].data[:duration_ns]?
      forced = capture_log { Timed.new.forced }[1].data[:duration_ns]?
      disabled = capture_log { Timed.new.disabled }[1].data[:duration_ns]?
      assert default.nil? == no_timing
      assert forced.nil? == no_timing
      assert disabled.nil?
      assert forced.nil? || forced.raw.is_a?(UInt64)
    end

    test "duration_ns is a whole number of nanoseconds" do
      duration = capture_log { Timed.new.pausing }[1].data[:duration_ns]?
      assert duration.nil? || (2_000_000...1_000_000_000).includes?(duration.as_u64)
    end

    test "exception entries carry the duration when timing is on" do
      entries = capture_log do
        Timed.new.failing
      rescue ArgumentError
      end
      assert entries[1].message == "!Timed#failing"
      assert entries[1].data[:duration_ns]?.nil? == {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
    end

    test "duration_ns covers the method, not converting its result" do
      duration = capture_log { Timed.new.slow_result }[1].data[:duration_ns]?
      assert duration.nil? || duration.as_u64 < 25_000_000
    end

    test "timing: that is not true or false fails to compile" do
      assert compile_error("timing_not_a_bool").to_s.includes?("logbuch: timing: must be true or false on Offender#go")
    end
  end
{% end %}
