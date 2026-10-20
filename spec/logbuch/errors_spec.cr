require "../spec_helper"
require "../../src/logbuch"

# Exception objects raised again on every call, one per test, since the
# tests run in random order and an exception is logged in full only once.
STORED_ERROR  = ArgumentError.new("stored")
WATCHED_ERROR = ArgumentError.new("watched")

class Stage
  include Logbuch::Annotations

  @[Logged]
  def fail(code : Int32) : Int32
    raise ArgumentError.new("failed #{code}")
  end

  @[Logged]
  def fail_stored : Int32
    raise STORED_ERROR
  end
end

class Pipeline
  include Logbuch::Annotations

  @[Logged]
  def run(code : Int32) : Int32
    Stage.new.fail(code)
  end

  @[Logged]
  def run_stored : Int32
    Stage.new.fail_stored
  end
end

# Logs only at info and above, like a production setup.
class Watcher
  include Logbuch::Annotations

  Log = ::Log.new("watcher", LOG_BACKEND, :info)

  @[Logged]
  def fail(code : Int32) : Int32
    raise ArgumentError.new("failed #{code}")
  end

  @[Logged]
  def fail_stored : Int32
    raise WATCHED_ERROR
  end

  @[Logged]
  def relay(code : Int32) : Int32
    Stage.new.fail(code)
  end

  @[Logged(slow: {ms: 50})]
  def wait(ms : Int32) : Int32
    sleep ms.milliseconds
    ms
  end
end

# An exception whose message raises.
class MutedError < Exception
  def message : String?
    raise SampleError.new("no message")
  end
end

# An exception whose class name raises.
class NamelessError < Exception
  def self.name : String
    raise SampleError.new("no name")
  end
end

class Breaker
  include Logbuch::Annotations

  @[Logged]
  def mute : Int32
    raise MutedError.new
  end

  @[Logged]
  def nameless : Int32
    raise NamelessError.new("nameless")
  end

  @[Logged]
  def through : Int32
    nameless
  end
end

{% unless %w[off 0].includes?(flag?(:logbuch)) %}
  describe ErrorLines do
    test "an error line is written at error, whatever the method's level" do
      entries = capture_log { Stage.new.fail(1) rescue nil }
      assert entries[0].severity.trace?
      assert entries[1].severity.error?
    end

    test "the error line carries the exception" do
      error = nil
      entries = capture_log do
        Stage.new.fail(1)
      rescue ex
        error = ex
      end
      assert entries[1].exception.same?(error)
      assert entries[1].data[:error].as_h["message"].as_s == "failed 1"
    end

    test "an exception is logged in full once; outer calls log only its type" do
      entries = capture_log { Pipeline.new.run(2) rescue nil }
      assert entries.map(&.message) == [">Pipeline#run", ">Stage#fail", "!Stage#fail", "!Pipeline#run"]
      assert entries[2].exception
      assert entries[2].data[:error].as_h["message"].as_s == "failed 2"
      assert entries[3].severity.error?
      assert entries[3].exception.nil?
      assert entries[3].data[:error].as_h == {"type" => Log::Metadata::Value.new("ArgumentError")}
    end

    test "an exception whose message raises is logged with its type and re-raised" do
      error = nil
      entries = capture_log do
        Breaker.new.mute
      rescue ex
        error = ex
      end
      assert error.is_a?(MutedError)
      assert entries[1].data[:error].as_h["type"].as_s == "MutedError"
      assert entries[1].data[:error].as_h["message"].as_s == "#<message raised SampleError>"
    end

    test "an exception whose class name raises is re-raised unchanged by every frame" do
      error = nil
      entries = capture_log do
        Breaker.new.through
      rescue ex
        error = ex
      end
      assert error.is_a?(NamelessError)
      assert entries.map(&.message) == [">Breaker#through", ">Breaker#nameless", "!Breaker#nameless", "!Breaker#through"]
      assert entries[2].data[:error].as_h["type"].as_s == "#<name raised>"
      assert entries[2].data[:error].as_h["message"].as_s == "nameless"
      assert entries[3].data[:error].as_h == {"type" => Log::Metadata::Value.new("#<name raised>")}
    end

    test "an exception raised again later is logged only by its type" do
      first = capture_log { Pipeline.new.run_stored rescue nil }
      assert first.map(&.message) == [">Pipeline#run_stored", ">Stage#fail_stored", "!Stage#fail_stored", "!Pipeline#run_stored"]
      assert first[2].exception.same?(STORED_ERROR)
      assert first[2].data[:error].as_h["message"].as_s == "stored"
      assert first[3].exception.nil?

      again = capture_log { Pipeline.new.run_stored rescue nil }
      assert again.map(&.message) == [">Pipeline#run_stored", ">Stage#fail_stored", "!Stage#fail_stored", "!Pipeline#run_stored"]
      assert again[2].exception.nil?
      assert again[2].data[:error].as_h == {"type" => Log::Metadata::Value.new("ArgumentError")}
      assert again[3].exception.nil?
      assert again[3].data[:error].as_h == {"type" => Log::Metadata::Value.new("ArgumentError")}
    end

    test "an exception raised again later through a disabled method is logged only by its type" do
      first = capture_log { Watcher.new.fail_stored rescue nil }
      assert first.map(&.message) == ["!Watcher#fail_stored"]
      assert first[0].exception.same?(WATCHED_ERROR)
      assert first[0].data[:error].as_h["message"].as_s == "watched"

      again = capture_log { Watcher.new.fail_stored rescue nil }
      assert again.map(&.message) == ["!Watcher#fail_stored"]
      assert again[0].exception.nil?
      assert again[0].data[:error].as_h == {"type" => Log::Metadata::Value.new("ArgumentError")}
    end

    test "a disabled call around an enabled one logs the exception only by type" do
      entries = capture_log { Watcher.new.relay(4) rescue nil }
      assert entries.map(&.message) == [">Stage#fail", "!Stage#fail", "!Watcher#relay"]
      assert entries[1].exception.is_a?(ArgumentError)
      assert entries[1].data[:error].as_h["message"].as_s == "failed 4"
      assert entries[2].exception.nil?
      assert entries[2].data[:error].as_h == {"type" => Log::Metadata::Value.new("ArgumentError")}
    end

    test "an error is logged even when the method's level is disabled" do
      entries = capture_log { Watcher.new.fail(3) rescue nil }
      assert entries.map(&.message) == ["!Watcher#fail"]
      assert entries[0].severity.error?
      assert entries[0].data[:duration_ns]?.nil?
    end

    test "a slow call is logged at its level when only that level is enabled" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      assert capture_log { Watcher.new.wait(0) }.empty?
      entries = capture_log { Watcher.new.wait(60) }
      assert entries.map(&.message) == (timing_off ? [] of String : ["<Watcher#wait"])
    end
  end
{% end %}
