require "../spec_helper"
require "../../src/logbuch"

# A log backend that fails on every entry, like a full disk.
class FailingBackend < Log::Backend
  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    raise IO::Error.new("disk full")
  end
end

Log.builder.bind("broken", :trace, FailingBackend.new)

module Broken
  Log = ::Log.for("broken")

  class Account
    include Logbuch::Annotations

    getter balance = 100

    @[Logged]
    def withdraw(amount : Int32) : Int32
      @balance -= amount
    end

    @[Logged]
    def reject(amount : Int32) : Int32
      raise ArgumentError.new("rejected #{amount}")
    end

    @[Logged]
    def each_coin(&) : Nil
      yield 1
      yield 2
    end
  end
end

# A backend that fails on the next line after `fail_next` is set and keeps
# the others.
class FlakyBackend < Log::Backend
  getter entries = [] of Log::Entry
  property? fail_next = false

  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    if fail_next?
      @fail_next = false
      raise IO::Error.new("disk full")
    end
    @entries << entry
  end
end

FLAKY_BACKEND = FlakyBackend.new

Log.builder.bind("flaky", :error, FLAKY_BACKEND)

module Flaky
  Log = ::Log.for("flaky")

  # Raises through two traced frames; `find` accepts a `KeyError` and logs it
  # at `:error`, so the flaky backend sees it.
  class Relay
    include Logbuch::Annotations

    @[Logged]
    def run(error : Exception) : Nil
      fail(error)
    end

    @[Logged]
    def fail(error : Exception) : Nil
      raise error
    end

    @[Logged]
    def look(error : Exception) : Nil
      find(error)
    end

    @[Logged]
    @[LogAccept(KeyError, :error)]
    def find(error : Exception) : Nil
      raise error
    end
  end
end

# The lines with *message* the flaky backend kept.
def flaky_lines(message : String) : Array(Log::Entry)
  FLAKY_BACKEND.entries.select { |entry| entry.message == message }
end

class Echo
  include Logbuch::Annotations

  @[Logged]
  def echo(value : Int32) : Int32
    Fiber.yield
    value
  end
end

describe Robustness do
  test "a failing log backend does not stop the method or change its result" do
    account = Broken::Account.new
    assert account.withdraw(30) == 70
    assert account.balance == 70
  end

  test "a failing log backend does not replace the method's own exception" do
    error = nil
    begin
      Broken::Account.new.reject(5)
    rescue ex
      error = ex
    end
    assert error.is_a?(ArgumentError)
    assert error.try(&.message) == "rejected 5"
  end

  test "a failing log backend does not break a block that leaves early" do
    coin = Broken::Account.new.each_coin { |value| break value }
    assert coin == 1
  end

  test "an error line the backend loses leaves the exception to the next frame, which logs it in full" do
    error = ArgumentError.new("bad")
    FLAKY_BACKEND.fail_next = true
    begin
      Flaky::Relay.new.run(error)
    rescue
    end
    assert flaky_lines("!Flaky::Relay#fail").empty?
    outer = flaky_lines("!Flaky::Relay#run")
    assert outer.size == 1
    assert outer[0].data[:error].as_h["message"].as_s == "bad"
    assert outer[0].exception.same?(error)
  end

  test "an accepted exception's line the backend loses leaves the exception to the next frame" do
    error = KeyError.new("gone")
    FLAKY_BACKEND.fail_next = true
    begin
      Flaky::Relay.new.look(error)
    rescue
    end
    assert flaky_lines("<Flaky::Relay#find").empty?
    outer = flaky_lines("!Flaky::Relay#look")
    assert outer.size == 1
    assert outer[0].data[:error].as_h["message"].as_s == "gone"
  end

  test "lines carry no fiber key" do
    entries = capture_log { Echo.new.echo(1) }
    assert entries.size == 2
    assert entries.none?(&.data[:fiber]?)
  end

  test "an application that sets the fiber name in Log.context gets it on every line" do
    done = Channel(Nil).new
    entries = capture_log do
      spawn(name: "worker-1") do
        Log.context.set(fiber: Fiber.current.name)
        Echo.new.echo(1)
        done.send(nil)
      end
      done.receive
    end
    assert entries.size == 2
    assert entries.all? { |entry| entry.context[:fiber].as_s == "worker-1" }
  end
end
