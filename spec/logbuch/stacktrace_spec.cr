require "../spec_helper"
require "../../src/logbuch"

# Every test raises a new exception, since an exception is logged in full only
# once in its lifetime.

@[Logbuch::Annotations::LogType(stacktrace: false)]
class QuietError < Exception
end

class QuieterError < QuietError
end

@[Logbuch::Annotations::LogType(stacktrace: true)]
class LoudAgainError < QuietError
end

class Stacks
  include Logbuch::Annotations

  @[Logged(:omit)]
  def plain(error : Exception) : Nil
    raise error
  end

  # The superclass comes first, so the order does not decide which entry wins.
  @[Logged(:omit)]
  @[LogError(IO::Error, LoudAgainError, stacktrace: false)]
  @[LogError(IO::TimeoutError, QuietError, stacktrace: true)]
  def mapped(error : Exception) : Nil
    raise error
  end

  @[Logged(:omit)]
  def outer(error : Exception) : Nil
    mapped(error)
  end
end

# Traced by its `@[LogError]` and `@[LogAccept]` alone, without `@[Logged]`
# and without an include, as a `@[Logged]` without arguments traces it.
class Unlabeled
  @[Logbuch::Annotations::LogError(KeyError, :warn)]
  def fail(error : Exception) : Int32
    raise error
  end

  @[Logbuch::Annotations::LogAccept(KeyError, :info)]
  def accept(error : Exception) : Int32
    raise error
  end
end

# The error line a traced call writes for *error*, which it raises.
def error_line(error : Exception, &) : Log::Entry
  entries = capture_log do
    yield error
  rescue
  end
  entries.find!(&.severity.error?)
end

describe Stacktraces do
  test "an exception type with stacktrace: false is logged in full without its stack trace" do
    line = error_line(QuietError.new("no stock")) { |raised| Stacks.new.plain(raised) }
    assert line.exception.nil?
    assert line.message == "!Stacks#plain"
    assert line.data[:error].as_h["type"].as_s == "QuietError"
    assert line.data[:error].as_h["message"].as_s == "no stock"
  end

  test "an exception type's subclass inherits its stacktrace:" do
    assert error_line(QuieterError.new) { |raised| Stacks.new.plain(raised) }.exception.nil?
  end

  test "a subclass with stacktrace: true gets its stack trace back" do
    error = LoudAgainError.new
    assert error_line(error) { |raised| Stacks.new.plain(raised) }.exception.same?(error)
  end

  test "any other exception keeps its stack trace" do
    error = KeyError.new
    assert error_line(error) { |raised| Stacks.new.plain(raised) }.exception.same?(error)
    error = KeyError.new
    assert error_line(error) { |raised| Stacks.new.mapped(raised) }.exception.same?(error)
  end

  test "a method's stacktrace: turns the stack trace off for a type and its subclasses" do
    line = error_line(IO::Error.new("closed")) { |raised| Stacks.new.mapped(raised) }
    assert line.exception.nil?
    assert line.data[:error].as_h["message"].as_s == "closed"
    assert error_line(IO::EOFError.new) { |raised| Stacks.new.mapped(raised) }.exception.nil?
  end

  test "the most specific entry of a method's stacktrace: wins" do
    error = IO::TimeoutError.new
    assert error_line(error) { |raised| Stacks.new.mapped(raised) }.exception.same?(error)
  end

  test "a method's stacktrace: overrides the exception type's, both ways" do
    error = QuieterError.new
    assert error_line(error) { |raised| Stacks.new.mapped(raised) }.exception.same?(error)
    assert error_line(LoudAgainError.new) { |raised| Stacks.new.mapped(raised) }.exception.nil?
  end

  test "the call where the exception first appears decides; an outer call logs only its type" do
    entries = capture_log do
      Stacks.new.outer(IO::Error.new("closed"))
    rescue
    end
    errors = entries.select(&.severity.error?)
    assert errors.map(&.message) == ["!Stacks#mapped", "!Stacks#outer"]
    assert errors.all?(&.exception.nil?)
    assert errors[0].data[:error].as_h.has_key?("message")
    assert errors[1].data[:error].as_h.keys == ["type"]
  end

  test "LogError and LogAccept take exception types, one level and stacktrace: true or false" do
    assert compile_error("log_error_not_an_exception").to_s.includes?("logbuch: @[LogError] takes exception types and one level, such as @[LogError(IO::Error, KeyError, :warn)], not String, on Offender#go")
    assert compile_error("log_error_two_levels").to_s.includes?("logbuch: @[LogError] takes exception types and one level, such as @[LogError(IO::Error, KeyError, :warn)], not :error, on Offender#go")
    assert compile_error("log_error_level_path").to_s.includes?("logbuch: @[LogError] takes exception types and one level, such as @[LogError(IO::Error, KeyError, :warn)], not Log::Severity::Loud, on Offender#go")
    assert compile_error("log_error_stacktrace_not_a_bool").to_s.includes?("logbuch: @[LogError] takes only stacktrace: true or false, on Offender#go")
    assert compile_error("moved_stacktrace_option").to_s.includes?("logbuch: stacktrace: is not an option of @[Logged]; use @[LogError(..., stacktrace: false)] on Offender#go")
  end

  test "an exception type is listed once, and one LogError goes without types" do
    assert compile_error("log_error_twice").to_s.includes?("logbuch: Missing is listed more than once in the @[LogError] and @[LogAccept] annotations of Offender#go")
    assert compile_error("log_error_and_accept").to_s.includes?("logbuch: KeyError is listed more than once in the @[LogError] and @[LogAccept] annotations of Offender#go")
    assert compile_error("log_error_two_fallbacks").to_s.includes?("logbuch: Offender#go has more than one @[LogError] without types")
  end

  test "LogError alone traces a method, at the level and detail of a plain @[Logged]" do
    entries = capture_log do
      Unlabeled.new.fail(KeyError.new("gone"))
    rescue KeyError
    end
    assert entries.map { |entry| {entry.severity, entry.message} } == [{Log::Severity::Trace, ">Unlabeled#fail"}, {Log::Severity::Warn, "!Unlabeled#fail"}]
    assert entries[0].data[:args].as_h["error"].as_h["message"].as_s == "gone"
  end

  test "LogAccept alone traces a method and logs the accepted exception as its result" do
    entries = capture_log do
      Unlabeled.new.accept(KeyError.new("gone"))
    rescue KeyError
    end
    assert entries.map { |entry| {entry.severity, entry.message} } == [{Log::Severity::Trace, ">Unlabeled#accept"}, {Log::Severity::Info, "<Unlabeled#accept"}]
  end

  test "stacktrace: on LogType takes true or false and goes only on exception classes" do
    assert compile_error("type_stacktrace_not_a_bool").to_s.includes?("logbuch: stacktrace: takes true or false, on @[LogType] of OffendingError")
    assert compile_error("type_stacktrace_traced").to_s.includes?("logbuch: stacktrace: goes on the @[LogType] of an exception class, not on Offender")
    assert compile_error("type_stacktrace_value").to_s.includes?("logbuch: stacktrace: goes on the @[LogType] of an exception class, not on Offender")
  end
end
