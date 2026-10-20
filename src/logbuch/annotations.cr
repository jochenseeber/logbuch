module Logbuch
  # The annotations that trace methods and control how values are logged.
  #
  # A program that includes this module at its top level writes them without
  # a prefix in every file, such as `@[Logged]` instead of
  # `@[Logbuch::Annotations::Logged]`; logbuch never includes it there
  # itself, so its names cannot clash with a program's or another shard's.
  # A shard that uses logbuch writes the full names, or includes the module
  # into its own types, so it works in any program. logbuch includes
  # `Logbuch::Tracing` into each type with a traced method.
  #
  # Including this module in a class, struct or module gives that type the
  # short names and includes `Logbuch::Tracing` into it, which a private type
  # needs, since logbuch cannot reopen it from outside its file. A private
  # top-level module, the modules inside it, and a type defined in the
  # program's own `macro finished` need it too: logbuch cannot see them, so
  # without it their methods are not traced, and the build does not fail.
  #
  # ```
  # require "logbuch"
  #
  # include Logbuch::Annotations
  #
  # class Shop
  #   @[Logged("placing the order", :debug)]
  #   @[LogError(IO::Error, :warn, stacktrace: false)]
  #   def place(order : Order, @[LogAs(:redacted)] coupon : String) : Receipt
  #   end
  # end
  # ```
  #
  # Wherever an annotation takes a level, it is a symbol, `:trace` to
  # `:fatal`, or the `Log::Severity` member, such as `Log::Severity::Warn` or
  # `::Log::Severity::Warn`. Wherever it takes a detail, it is a symbol,
  # `:omit` to `:full`, or the `Logbuch::Detail` member, such as
  # `Logbuch::Detail::Full`.
  module Annotations
    # Traces a method of a class, struct or module. Its positional arguments
    # are told apart by what they are, in any order:
    #
    # - a string: the description, such as `"placing the order"`, which the
    #   messages are built from;
    # - a level, `:trace` (the default) to `:fatal`, or a `Log::Severity`
    #   member such as `Log::Severity::Debug`: the severity of the entry and
    #   exit lines;
    # - a detail, `:omit`, `:id`, `:summary` (the default) or `:full`, or a
    #   `Logbuch::Detail` member such as `Logbuch::Detail::Full`: how much of
    #   the arguments and the result is logged.
    #
    # Its named options:
    #
    # - `timing:` whether the lines carry `duration_ns`, on by default;
    # - `result:` a block in arrow notation with one parameter, whose result is
    #   logged instead of the method's result;
    # - `slow:` a named tuple such as `{ms: 200, level: :warn}`: the exit line of
    #   a call that took at least 200 ms is written at `:warn`, the default
    #   level, which must be above the method's level, and carries
    #   `slow: true`; with `args: true`, it
    #   also carries the arguments when the entry line is disabled;
    # - `lock:` a lock, such as `@lock`, held while the arguments and the result
    #   are converted, but not while the method runs;
    # - `log:` the log the lines go to instead of the type's: a source name such
    #   as `"shop.export"`, a name below the type's log such as `".export"`, or a
    #   constant that holds a `Log`.
    annotation Logged
    end

    # Sets how a parameter or field is logged. Its positional arguments, in any
    # order:
    #
    # - a detail, `:omit`, `:id`, `:summary` or `:full`, or a `Logbuch::Detail`
    #   member such as `Logbuch::Detail::Full`: a parameter is logged at that
    #   detail, whatever the method's; a field is included from that detail
    #   up, and an `:omit` one never;
    # - `:redacted`: the value is always logged as `"***"`, and a `converter:`
    #   next to it fails the build; a converter that masks a value goes
    #   without it. Without a detail next to it, the parameter or field is
    #   logged where it would be without the annotation;
    # - `items(...)`, on a collection: how each of its items is logged (see
    #   below).
    #
    # Its named options: `converter:`, a block in arrow notation with one
    # parameter whose result is logged instead of the value, and the limits
    # `cap:` and `length:`. They can go without a positional argument, as in
    # `@[LogAs(length: 80)]`; the parameter or field then keeps the detail it
    # has without the annotation. Crystal takes positional arguments before
    # named ones, so `items(...)` goes before them.
    #
    # The limits apply to the value, or to what `converter:` returns:
    #
    # - `cap:` limits the items of the annotated array, deque, set, slice or
    #   hash itself; a tuple is logged whole;
    # - `length:` cuts the annotated string itself, the keys of the annotated
    #   hash, an exception's message, the `inspect` text of an object logged
    #   with `inspect`, or the identity of an object logged as its identity.
    #
    # How deep the values below the value nest is the `max_depth` setting
    # only (see `Logbuch.configure`).
    #
    # `items(...)` sets how each item of the annotated collection is logged:
    # the values of an array, deque, set, slice, hash or named tuple, and the
    # elements of a tuple. It takes a detail, `:id`, `:summary` or `:full` or
    # a `Logbuch::Detail` member, which the item and what is inside it are
    # logged at, higher or lower than the collection's own, and the named
    # options `cap:`, `length:` and `converter:`, which apply to each item as
    # they would to the value: `@[LogAs(:summary, items(:id, length: 20),
    # cap: 10)]` logs ten items at most, each at `:id` with its strings cut to
    # 20 characters. A `converter:` of the collection runs first, and
    # `items(...)` applies to what it returns; the item converter runs for each
    # item while the collection is converted. A hash's keys are logged at
    # `:id` whatever it says, and inside an identity, where every value is
    # logged at `:id`, it has no effect. It fails the build on `:omit`, next
    # to `:redacted`, and on a value that is none of those
    # collections.
    #
    # The strings and collections inside the value get the settings again, not
    # `cap:` and `length:`; `items(...)` sets them for its items. Without a
    # converter, `cap:` on a type that is not one of those collections, and
    # `length:` on a type it cannot cut, such as a number, a character, `Bool`,
    # a symbol, an enum, an array or tuple, or an object logged by its fields,
    # fail the build, and so do the options of `items(...)` that cannot change
    # how its items are logged, unless it has a converter of its own. A union,
    # a parameter without a type, and a type with its own `to_trace` are not
    # checked.
    #
    # At `:id`, every object is logged as its identity, such as
    # `"o-17"`, which is the same at any depth. So on a parameter logged at
    # `:id`, by its own detail or the method's, `length:` cuts each string of
    # it, also for an object logged by its fields. A field's detail only sets
    # from which detail it is shown; its value is logged at the detail of the
    # object around it, so `length:` on a field marked `:id` cuts the identity
    # the field shows at `:id`.
    annotation LogAs
    end

    # Sets how a traced method logs the exceptions of the listed types and
    # their subclasses: `@[LogError(IO::Error, KeyError, :warn,
    # stacktrace: false)]` writes their error lines at `:warn` (`:error` by
    # default) without the stack trace (by default, the exception type's
    # `@[LogType(stacktrace:)]` decides). The level can also be a
    # `Log::Severity` member, as in `@[LogError(IO::Error,
    # Log::Severity::Warn)]`. Without types, it applies to every
    # exception the method's other `LogError` annotations do not list. A method
    # can carry several; the most specific type wins. On a method without
    # `@[Logged]`, it traces the method, as a `@[Logged]` without arguments
    # does.
    annotation LogError
    end

    # Lists exceptions that end a traced method's call like a result:
    # `@[LogAccept(KeyError, :info)]` logs a `KeyError` on the exit line, at
    # `:info` (the method's level by default; `Log::Severity::Info` works too),
    # and the method raises it again.
    # With `stacktrace: true` (`false` by default), the exit line carries the
    # exception. A method can carry several; the most specific type wins. On a
    # method without `@[Logged]`, it traces the method, as a `@[Logged]`
    # without arguments does.
    annotation LogAccept
    end

    # Logs instances of a class or struct, and of its subclasses, by their
    # fields. A type is also logged by its fields when it includes
    # `Logbuch::Tracing`, or when any of its fields or `initialize` parameters
    # carries `@[LogAs]`; any other type without its own `to_trace` is logged
    # with `inspect`.
    #
    # `@[LogType(lock: @lock)]` converts the fields while holding the lock.
    #
    # `@[LogType(log: "payments")]` sends the lines of the type's traced
    # methods, and its subclasses', to another log. It takes what the `log:`
    # option of `Logged` takes; a name that starts with a dot is below the log
    # the type would have without it.
    #
    # `@[LogType(inspect: :full)]` sets the detail of the `inspect` logbuch
    # writes for an opted-in type without one of its own: `:summary` by
    # default, `:id` or `:full`, or `:off` to keep Crystal's `inspect`. It
    # shows the fields shown at that detail, `:redacted` ones as `"***"`.
    #
    # `@[LogType(stacktrace: false)]` on an exception class logs it, and its
    # subclasses, without the stack trace: the error line keeps the
    # exception's data but does not attach the exception, which formatters
    # print with its stack trace. A subclass can set `stacktrace: true` again,
    # and a traced method's `@[LogError]` overrides it.
    annotation LogType
    end

    # The program's include at the top level only brings the names. Including
    # `Logbuch::Tracing` into this module instead would run its hook for this
    # module, not for the including type.
    macro included
      {% unless @type == @top_level %}
        include ::Logbuch::Tracing
      {% end %}
    end
  end
end
