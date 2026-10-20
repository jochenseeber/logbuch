# Log levels, sources and timing: choose the severity per method, filter by
# source with the usual `Log.setup`, give a method or a type its own source
# with `log:`, turn timing on or off, raise the level of slow calls with
# `slow:`, and control how a type is logged with `to_trace`
# (examples/to_trace.cr shows more of it).
#
#   crystal run examples/levels_and_sources.cr
#   crystal run -Dlogbuch_timing=off examples/levels_and_sources.cr
#   crystal run -Dlogbuch=off examples/levels_and_sources.cr
#
# The levels are those of the stdlib `Log`, so a program that calls
# `Log.setup_from_env` instead of `Log.setup` shows the trace lines with
# LOG_LEVEL=TRACE.

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"

# Billing and history log everything, auditing only from info up, except for
# reconciling, which has a source of its own.
Log.setup do |config|
  backend = Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync)
  config.bind "billing", :trace, backend
  config.bind "history", :trace, backend
  config.bind "audit", :info, backend
  config.bind "audit.reconcile", :trace, backend
end

# A constant that holds a log, for `log:` below.
HISTORY_LOG = Log.for("history")

# A type can decide how it shows up in a trace by overriding `to_trace`.
struct InvoiceNumber
  def initialize(@year : Int32, @serial : Int32)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new("INV-#{@year}-#{@serial.to_s.rjust(5, '0')}")
  end
end

# Without a Log constant, a type logs under its own name: "billing".
class Billing
  @[Logged("creating an invoice")]
  def create(customer : String) : InvoiceNumber
    InvoiceNumber.new(2026, 42)
  end

  # No duration on this one.
  @[Logged("sending an invoice", timing: false)]
  def send_invoice(number : InvoiceNumber) : Bool
    true
  end

  @[Logged("closing the books", :info)]
  def close : Nil
  end

  # A call of 50 ms or more writes its exit line at warn.
  @[Logged("archiving the invoices", slow: {ms: 50, level: :warn})]
  def archive(pause : Time::Span) : Int32
    sleep pause
    12
  end

  # log: takes a source name, here "history" ...
  @[Logged("recording a payment", log: "history")]
  def record(number : InvoiceNumber) : Bool
    true
  end

  # ... or a constant that holds a log. The level can also be a
  # `Log::Severity` member.
  @[Logged("printing an invoice", Log::Severity::Debug, log: HISTORY_LOG)]
  def print(number : InvoiceNumber) : Bool
    true
  end
end

class Auditor
  # The type's own Log constant sets the source.
  Log = ::Log.for("audit")

  # At the default trace level, this is filtered out for the "audit" source.
  @[Logged("checking an invoice")]
  def check(number : InvoiceNumber) : Bool
    true
  end

  # At info, it gets through.
  @[Logged("approving an invoice", :info)]
  def approve(number : InvoiceNumber) : Bool
    true
  end

  # Only a slow call gets through, at warn; args: true puts its arguments on
  # the exit line, since the entry line is filtered out.
  @[Logged("exporting the invoices", slow: {ms: 50, args: true})]
  def export(pause : Time::Span) : Int32
    sleep pause
    12
  end

  # A name that starts with a dot is below the type's log: "audit.reconcile",
  # which Log.setup lets through from trace up.
  @[Logged("reconciling the books", log: ".reconcile")]
  def reconcile(month : Int32) : Bool
    true
  end

  # At trace, its entry and exit lines are filtered out for "audit", but an
  # error line is written whatever the method's level.
  @[Logged("voiding an invoice")]
  def void(number : InvoiceNumber) : Bool
    raise ArgumentError.new("invoice is paid")
  end
end

# log: on the type sends all its traced methods to another source.
@[LogType(log: "billing")]
class Refunds
  @[Logged("refunding an invoice")]
  def refund(number : InvoiceNumber) : Bool
    true
  end
end

billing = Billing.new
auditor = Auditor.new

puts "# to_trace turns the invoice number into a string; timing: false drops duration_ns:"
number = billing.create("Ada")
billing.send_invoice(number)

puts "\n# The level :info writes the lines at info:"
billing.close

puts "\n# slow: writes the slow call's exit line at warn (not with -Dlogbuch_timing=off):"
billing.archive(1.millisecond)
billing.archive(60.milliseconds)

puts "\n# The audit source is set to info, so only the info-level call shows up:"
auditor.check(number)
auditor.approve(number)

puts "\n# Only the slow export shows up, with its arguments (not with -Dlogbuch_timing=off):"
auditor.export(1.millisecond)
auditor.export(60.milliseconds)

puts "\n# log: \".reconcile\" logs under audit.reconcile, which is on from trace up:"
auditor.reconcile(10)

puts "\n# Refunds logs under billing, as its log: says:"
Refunds.new.refund(number)

puts "\n# log: with a source name or a constant that holds a log sends a method's lines there:"
billing.record(number)
billing.print(number)

puts "\n# An error line shows although the method's level is filtered out, without duration_ns:"
begin
  auditor.void(number)
rescue error : ArgumentError
  puts "(caught #{error.class})"
end
