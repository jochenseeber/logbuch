require "../spec_helper"

# The compile-error fixtures that compile with `-Dlogbuch=off`, each with the
# reason. Every other one must fail there with the error it fails with in the
# default build.
COMPILE_WITH_TRACING_OFF = {
  "tracing_probe" => "fails exactly when the wrappers are generated, to show that the flag turns tracing off",
}

# The last error line of a compiler run's *output*, or nil if it compiled.
def last_error(output : String?) : String?
  output.try(&.lines.reverse_each.find(&.includes?("Error:")))
end

describe BuildChecks do
  test "every compile-error fixture fails the same way with -Dlogbuch=off" do
    names = Dir.glob(File.join(__DIR__, "..", "fixtures", "compile_errors", "*.cr")).map { |path| File.basename(path, ".cr") }.sort!
    compiled = names.select { |name| compile_error(name, flags: ["logbuch=off"]).nil? }
    unexpected = compiled - COMPILE_WITH_TRACING_OFF.keys
    assert unexpected.empty?
    stale = COMPILE_WITH_TRACING_OFF.keys - compiled
    assert stale.empty?
    differing = (names - compiled).reject { |name| last_error(compile_error(name)) == last_error(compile_error(name, flags: ["logbuch=off"])) }
    assert differing.empty?
  end

  test "a type's annotations are checked when the type is never converted" do
    assert compile_error("type_option_unused").to_s.includes?("logbuch: @[LogType] takes only lock:, log: and inspect:, and stacktrace: on an exception class, such as @[LogType(lock: @lock)], on Offender")
    assert compile_error("field_unused").to_s.includes?("logbuch: @[LogAs] takes :omit, :id, :summary, :full, :redacted or items(...), not :bogus, on field Offender@name")
    assert compile_error("field_limit_unused").to_s.includes?("logbuch: length: has no effect on Int32: it cuts a string or inspect text only, on field Offender@count")
    assert compile_error("init_param_limit_unused").to_s.includes?("logbuch: length: has no effect on Int32: it cuts a string or inspect text only, on parameter count of Offender#initialize")
  end

  test "an exception class's LogType takes only lock:, log: and stacktrace:" do
    assert compile_error("exception_type_unknown_option").to_s.includes?("logbuch: @[LogType] takes only lock:, log: and inspect:, and stacktrace: on an exception class, such as @[LogType(lock: @lock)], on OffendingError")
  end

  test "the methods of a type logbuch does not trace are checked" do
    assert compile_error("detail_on_method_untraced_type").to_s.includes?("logbuch: @[LogAs] goes on parameters and fields; trace Offender#go with @[Logged] and give it the detail, such as @[Logged(:full)]")
    assert compile_error("param_untraced_method").to_s.includes?("logbuch: @[LogAs] takes :omit, :id, :summary, :full, :redacted or items(...), not :bogus, on parameter name of Offender#go")
    assert compile_error("trace_on_parameter_untraced").to_s.includes?("logbuch: @[Logged] goes on methods; use @[LogAs] on parameter name of Offender#go")
  end

  test "a traced method's log and messages are checked when it is never called" do
    assert compile_error("message_not_a_string_uncalled").to_s.includes?("logbuch: the exit_message converter must expand to a String, not Int32, on Offender#go")
    assert compile_error("log_computed_uncalled").to_s.includes?("logbuch: log: takes a constant that holds a Log, not a String")
  end
end
