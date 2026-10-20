require "../spec_helper"
require "../../src/logbuch"

# Every test raises a new exception, since an exception is logged in full only
# once in its lifetime.

class Desk
  include Logbuch::Annotations

  Log = ::Log.for("desk")

  # The superclass comes first, so the order does not decide which entry
  # wins: an IO::TimeoutError is an error, any other IO::Error is accepted.
  @[Logged(:omit)]
  @[LogAccept(IO::Error, :info)]
  @[LogError(IO::TimeoutError, :warn, stacktrace: false)]
  @[LogError(:fatal)]
  def handle(error : Exception) : Nil
    raise error
  end

  @[Logged(:omit)]
  @[LogAccept(KeyError, stacktrace: true)]
  @[LogError(ArgumentError)]
  def lookup(error : Exception) : Nil
    raise error
  end
end

# The levels of `Desk#handle` written as `Log::Severity` paths, with and
# without the leading `::`.
class PathDesk
  include Logbuch::Annotations

  @[Logged(:omit)]
  @[LogAccept(KeyError, Log::Severity::Info)]
  @[LogError(IO::Error, ::Log::Severity::Warn)]
  @[LogError(Log::Severity::Fatal)]
  def handle(error : Exception) : Nil
    raise error
  end
end

# Several `@[LogAccept]`, one per level and setting. The superclass comes
# first, so the order does not decide which entry wins.
class Counter
  include Logbuch::Annotations

  @[Logged(:omit)]
  @[LogAccept(KeyError)]
  @[LogAccept(IO::Error, :info)]
  @[LogAccept(IO::TimeoutError, :warn, stacktrace: true)]
  def settle(error : Exception) : Nil
    raise error
  end
end

# Accepted exceptions of calls that may be slow.
class SlowDesk
  include Logbuch::Annotations

  @[Logged(slow: {ms: 50, level: :error})]
  @[LogAccept(KeyError, :info)]
  def wait(ms : Int32) : Int32
    sleep ms.milliseconds
    raise KeyError.new("after #{ms}")
  end

  @[Logged(slow: {ms: 50, level: :error})]
  @[LogAccept(KeyError, :fatal)]
  def wait_loudly(ms : Int32) : Int32
    sleep ms.milliseconds
    raise KeyError.new("after #{ms}")
  end

  @[Logged(slow: {ms: 50, args: true})]
  @[LogAccept(KeyError)]
  def wait_with_args(ms : Int32) : Int32
    sleep ms.milliseconds
    raise KeyError.new("after #{ms}")
  end
end

# Raises an exception through two traced frames, the outer with a level of
# its own for it.
class ErrorRelay
  include Logbuch::Annotations

  @[Logged(:omit)]
  @[LogError(ArgumentError, :warn)]
  def forward(error : Exception) : Nil
    fail(error)
  end

  @[Logged(:omit)]
  def fail(error : Exception) : Nil
    raise error
  end
end

# Runs the block with the desk log at *level*.
def desk_at(level : ::Log::Severity, &)
  Desk::Log.level = level
  yield
ensure
  Desk::Log.level = :trace
end

# The entries a call to *method* of `Desk` with *error* writes.
def desk_entries(error : Exception, method = :handle) : Array(Log::Entry)
  capture_log do
    method == :handle ? Desk.new.handle(error) : Desk.new.lookup(error)
  rescue
  end
end

# Accepts a `KeyError` in `find`, which `run` calls without accepting it.
class Finder
  include Logbuch::Annotations

  Log = ::Log.for("finder")

  @[Logged(:omit, :info)]
  @[LogAccept(KeyError)]
  def find(error : Exception) : Nil
    raise error
  end
end

class FinderCaller
  include Logbuch::Annotations

  Log = ::Log.for("finder_caller")

  @[Logged(:omit)]
  def run(error : Exception) : Nil
    Finder.new.find(error)
  end
end

# The lines a `FinderCaller#run` with *error* writes, all sources together.
def finder_entries(error : Exception) : Array(Log::Entry)
  capture_log do
    FinderCaller.new.run(error)
  rescue
  end
end

# The entries the block writes; the exception it raises is rescued.
def rescued_log(&) : Array(Log::Entry)
  capture_log do
    yield
  rescue
  end
end

# The last line a call to `PathDesk#handle` with *error* writes.
def path_desk_line(error : Exception) : Log::Entry
  entries = capture_log do
    PathDesk.new.handle(error)
  rescue
  end
  entries.last
end

describe LogErrorAndAccept do
  test "LogError sets the level and the stack trace of the error line" do
    line = desk_entries(IO::TimeoutError.new("slow")).last
    assert line.severity.warn?
    assert line.message == "!Desk#handle"
    assert line.exception.nil?
    assert line.data[:error].as_h["type"].as_s == "IO::TimeoutError"
  end

  test "LogError without types sets the level for every other exception" do
    error = RuntimeError.new("boom")
    line = desk_entries(error).last
    assert line.severity.fatal?
    assert line.exception.same?(error)
  end

  test "an error without a LogError is written at :error with its stack trace" do
    error = ArgumentError.new("bad")
    line = desk_entries(error, :lookup).last
    assert line.severity.error?
    assert line.exception.same?(error)
  end

  test "LogAccept logs the exception as the result at its level, and the most specific type wins" do
    line = desk_entries(IO::Error.new("closed")).last
    assert line.severity.info?
    assert line.message == "<Desk#handle"
    assert line.data[:result].as_h["type"].as_s == "IO::Error"
    assert line.exception.nil?
  end

  test "LogAccept defaults to the method's level and can carry the stack trace" do
    error = KeyError.new("k")
    line = desk_entries(error, :lookup).last
    assert line.severity.trace?
    assert line.data[:result].as_h["type"].as_s == "KeyError"
    assert line.exception.same?(error)
  end

  test "an accepted exception's level above the method's is written when only it is enabled" do
    entries = desk_at(:info) { desk_entries(IO::Error.new("closed")) }
    assert entries.map(&.severity) == [::Log::Severity::Info]
    assert entries[0].data[:result].as_h["type"].as_s == "IO::Error"
  end

  test "an error's level is checked on its own" do
    assert desk_at(:error) { desk_entries(IO::TimeoutError.new("slow")) }.empty?
    assert desk_at(:error) { desk_entries(RuntimeError.new("boom")) }.map(&.severity) == [::Log::Severity::Fatal]
  end

  test "several LogAccept set a level each, and the most specific type wins" do
    lines = [KeyError.new("k"), IO::Error.new("closed"), IO::TimeoutError.new("slow"), IO::EOFError.new("end")].map do |error|
      rescued_log { Counter.new.settle(error) }.last
    end
    assert lines.all? { |line| line.message == "<Counter#settle" }
    assert lines.map(&.severity) == [::Log::Severity::Trace, ::Log::Severity::Info, ::Log::Severity::Warn, ::Log::Severity::Info]
    assert lines.map(&.data[:result].as_h["type"].as_s) == ["KeyError", "IO::Error", "IO::TimeoutError", "IO::EOFError"]
    assert lines.map(&.exception.nil?) == [true, true, false, true]
    assert lines[2].exception.is_a?(IO::TimeoutError)
  end

  test "an accepted exception's exit line gets slow:'s level when the call was slow and that level is higher" do
    timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
    fast = rescued_log { SlowDesk.new.wait(0) }
    slow = rescued_log { SlowDesk.new.wait(60) }
    assert fast.map(&.message) == [">SlowDesk#wait", "<SlowDesk#wait"]
    assert fast[1].severity.info?
    assert slow.map(&.message) == [">SlowDesk#wait", "<SlowDesk#wait"]
    assert slow[1].data[:result].as_h["type"].as_s == "KeyError"
    # With timing off, no call is known to be slow.
    assert slow[1].severity == (timing_off ? ::Log::Severity::Info : ::Log::Severity::Error)
  end

  test "an accepted exception's level above slow:'s is kept on a slow call" do
    slow = rescued_log { SlowDesk.new.wait_loudly(60) }
    assert slow[1].message == "<SlowDesk#wait_loudly"
    assert slow[1].severity.fatal?
  end

  test "slow: args: true adds the arguments to a slow accepted exit line without an entry line" do
    timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
    log = ::Log.for("slow_desk")
    log.level = :info
    assert rescued_log { SlowDesk.new.wait_with_args(0) }.empty?
    entries = rescued_log { SlowDesk.new.wait_with_args(60) }
    if timing_off
      assert entries.empty?
    else
      assert entries.map(&.message) == ["<SlowDesk#wait_with_args"]
      assert entries[0].severity.warn?
      assert entries[0].data[:args].as_h["ms"].as_i == 60
      assert entries[0].data[:result].as_h["type"].as_s == "KeyError"
    end
  ensure
    ::Log.for("slow_desk").level = :trace
  end

  test "an outer call logs the exception's type at the level of its own LogError" do
    error = ArgumentError.new("bad")
    errors = rescued_log { ErrorRelay.new.forward(error) }.select(&.message.starts_with?("!"))
    assert errors.map(&.message) == ["!ErrorRelay#fail", "!ErrorRelay#forward"]
    assert errors.map(&.severity) == [::Log::Severity::Error, ::Log::Severity::Warn]
    assert errors[0].exception.same?(error)
    assert errors[0].data[:error].as_h["message"].as_s == "bad"
    assert errors[1].exception.nil?
    assert errors[1].data[:error].as_h == {"type" => Log::Metadata::Value.new("ArgumentError")}
  end

  test "LogError and LogAccept take a level as a Log::Severity path" do
    errors = [KeyError.new("k"), IO::Error.new("closed"), RuntimeError.new("boom")]
    severities = errors.map { |error| path_desk_line(error).severity }
    assert severities == [::Log::Severity::Info, ::Log::Severity::Warn, ::Log::Severity::Fatal]
  end

  test "an accepted exception counts as logged, so a caller that does not accept it logs only its type" do
    error = KeyError.new("missing")
    entries = finder_entries(error)
    accepted = entries.find! { |entry| entry.message == "<Finder#find" }
    assert accepted.data[:result].as_h["message"].as_s == "missing"
    caller_error = entries.find! { |entry| entry.message == "!FinderCaller#run" }
    assert caller_error.data[:error].as_h.keys == ["type"]
    assert caller_error.exception.nil?
  end

  test "an accepted exception whose exit line is disabled is logged in full by the caller" do
    ::Log.for("finder").level = :warn
    error = KeyError.new("missing")
    entries = finder_entries(error)
    ::Log.for("finder").level = :trace
    assert entries.none? { |entry| entry.message == "<Finder#find" }
    caller_error = entries.find! { |entry| entry.message == "!FinderCaller#run" }
    assert caller_error.data[:error].as_h["message"].as_s == "missing"
    assert caller_error.exception.same?(error)
  end
end
