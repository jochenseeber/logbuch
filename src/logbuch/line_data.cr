require "exception"
require "hash"
require "log"
require "named_tuple"
require "proc"
require "string"
require "time"

require "./convert"

# :nodoc:
class Exception
  # :nodoc:
  #
  # Whether a traced call has logged this exception in full. Nothing clears
  # it, so every later error line for this object, also one written when it
  # is raised again, logs only its type.
  property? __logbuch_logged = false

  # :nodoc:
  #
  # Whether a traced call logs this exception with its stack trace, unless
  # the method's `@[LogError]` says otherwise: the `stacktrace:` of the
  # nearest class, this one or an ancestor, that has one in its
  # `@[LogType]`, or `true`. The macro code expands once per exception
  # class, so the answer is a constant per class. The top-level
  # `macro finished` in `tracing.cr` has checked the value.
  def __logbuch_stacktrace? : Bool
    {% begin %}
      {% chain = ([@type] + @type.ancestors).select { |type| (anno = type.annotation(::Logbuch::Annotations::LogType)) && !anno[:stacktrace].nil? } %}
      {{ chain.empty? ? true : chain[0].annotation(::Logbuch::Annotations::LogType)[:stacktrace] }}
    {% end %}
  end
end

module Logbuch
  # The keys of the data on a trace line, for queries and formatters that
  # read them. A line's data is a `Log::Metadata`, whose keys are symbols; an
  # error's `type`, `message` and `cause` are keys of a hash inside it, which
  # are strings.
  #
  # ```
  # entry.data[Logbuch::Keys::RESULT]?
  # entry.data[Logbuch::Keys::ERROR].as_h[Logbuch::Keys::MESSAGE]
  # ```
  module Keys
    # The traced method's label, such as `"Shop::Checkout#place"`; on every
    # line.
    METHOD = :method

    # The arguments, a hash with one key per argument; on the entry line.
    ARGS = :args

    # The result, or an accepted exception; on the exit line.
    RESULT = :result

    # The exception; on the error line.
    ERROR = :error

    # The call's duration in whole nanoseconds; on the exit line, and on the
    # error line when the method's level is enabled.
    DURATION = :duration_ns

    # `true` on the exit line of a call that took at least its `slow:`
    # threshold; left out of every other line.
    SLOW = :slow

    # An exception's class name.
    TYPE = "type"

    # An exception's message.
    MESSAGE = "message"

    # An exception's cause, converted like the exception.
    CAUSE = "cause"
  end

  # :nodoc:
  #
  # Writes one trace line to *log*: *message* at *severity*, with the data
  # `method`, *args* if given, *entries*, and `slow: true` if *slow*, and
  # *exception* attached, if
  # *severity* is enabled for *log*, and returns whether it handed the line
  # to the backend. A log backend that raises loses the line and never
  # changes what the traced method does.
  #
  # Kept out of line, so each traced method calls it instead of carrying its
  # own copy.
  @[NoInline]
  def self.__line(log : ::Log, *, severity : ::Log::Severity, message : String, method : String, entries : NamedTuple, exception : Exception? = nil, args : ::Log::Metadata::Value? = nil, slow : Bool = false) : Bool
    return false unless log.level <= severity && (backend = log.backend)
    data = args ? ::Log::Metadata.build({method: method, args: args}.merge(entries)) : __data(method, entries)
    # Added last, and only to a slow call's line, so no other line pays for it.
    data = data.extend({slow: true}) if slow
    backend.dispatch(::Log::Entry.new(log.source, severity, message, data, exception))
    true
  rescue
    false
  end

  # :nodoc:
  #
  # Writes the error line of a traced call that raised *error*, at
  # *severity*, whatever the method's level. The call where the exception
  # first appears logs it in full and attaches it, so a formatter or error
  # backend reports its stack trace once; the calls it passes through after
  # that, and the calls it passes through when it is raised again, log only
  # its type; one whose line the backend loses is left to the next call to log
  # in full. *severity* and *stacktrace* are what the method's `@[LogError]`
  # says about *error*; a *stacktrace* of `nil` asks the exception's type, and
  # when the answer is `false`, the exception is logged in full but not
  # attached, so no stack trace is reported. Anything that raises here loses
  # the line, never the traced method's own exception.
  @[NoInline]
  def self.__error(log : ::Log, *, message : String, method : String, error : Exception, duration : UInt64?, severity : ::Log::Severity, stacktrace : Bool?) : Nil
    return unless log.level <= severity
    full = !error.__logbuch_logged?
    if full
      data = __convert(error, Detail::Summary)
      attached = error if stacktrace.nil? ? error.__logbuch_stacktrace? : stacktrace
    else
      data = ::Log::Metadata::Value.new({"type" => ::Log::Metadata::Value.new(__type_name(error))})
      attached = nil
    end
    written = if duration
                __line(log, severity: severity, message: message, method: method, entries: {error: data, duration_ns: duration}, exception: attached)
              else
                __line(log, severity: severity, message: message, method: method, entries: {error: data}, exception: attached)
              end
    error.__logbuch_logged = true if full && written
  rescue
  end

  # :nodoc:
  #
  # The name of *value*'s class, or a placeholder if a class overrides `name`
  # with one that raises.
  #
  # The compiler treats `name` and `Exception#message` as unable to raise, so
  # a `rescue` around a direct call never sees what an override raises; a call
  # through a proc does.
  def self.__type_name(value) : String
    -> { value.class.name }.call
  rescue
    "#<name raised>"
  end

  # :nodoc:
  #
  # The message of *error*, or a placeholder if its `message` raises; called
  # through a proc for the reason `__type_name` gives.
  def self.__message(error : Exception) : String?
    -> { error.message }.call
  rescue exception
    "#<message raised #{__type_name(exception)}>"
  end

  # :nodoc:
  #
  # The whole nanoseconds in *span*, counted without floating point. A
  # monotonic clock never measures a negative span; if one did, it counts as
  # 0 rather than raise in the traced method's wrapper.
  def self.__nanoseconds(span : Time::Span) : UInt64
    return 0_u64 if span.negative?
    span.to_i.to_u64 * 1_000_000_000 + span.nanoseconds.to_u64
  end

  # :nodoc:
  #
  # The data of one trace line: `method`, then *entries*. Built straight from
  # named tuples, so the only allocation is the `Log::Metadata` itself.
  def self.__data(method : String, entries : NamedTuple) : ::Log::Metadata
    ::Log::Metadata.build({method: method}.merge(entries))
  end
end
