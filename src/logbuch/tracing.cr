require "exception"
require "fiber"
require "log"
require "named_tuple"
require "string"
require "time"
require "tuple"

require "./annotations"
require "./line_data"
require "./detail"
require "./fields"
require "./convert"
require "./fiber_state"
require "./limits"
require "./logs"
require "./messages"
require "./values"

module Logbuch
  # Traces the methods of the including class, struct or module that carry
  # `@[Logged]`. logbuch includes it in every type with such a method, except
  # a private type or one inside a private type, which includes it, or
  # `Logbuch::Annotations`, itself; the build fails until it does.
  #
  # A private top-level module, the modules inside it, and a type defined in
  # the program's own `macro finished` must include it themselves too, but the
  # build does not fail without it: logbuch cannot see them, so their methods
  # are not traced until they do. An enum cannot include a module, so
  # `@[Logged]` on a method of an enum fails the build.
  #
  # Each traced method gets a wrapper with the same signature that logs entry,
  # calls the original method with `previous_def`, and logs exit or exception.
  # Subclasses of an including class are traced too. A module's traced
  # methods are wrapped in the module, so they are traced wherever they are
  # called: through any class that includes the module, or on the module
  # itself.
  #
  # A wrapper belongs to the type that defines the method, so an inherited
  # method logs with that type's label and log: with `class Plain < Base`,
  # `Plain.new.foo` logs `Base#foo` under `base`, whatever `Log` or
  # `@[LogType(log: …)]` `Plain` has. An override with its own `@[Logged]`
  # that calls `super` logs the call as `Plain#foo` instead.
  module Tracing
    macro included
      # A type that already has its hooks, from an earlier include or as a
      # subclass of a traced class, gets nothing new: a second set would
      # trace every call twice and define its subclasses' log twice. A type
      # that only includes a traced module has no log of its own yet, so its
      # own methods get their hooks here.
      {% unless @type.has_constant?("LOGBUCH_LOG") %}
        ::Logbuch::Tracing.__define_log

        macro finished
          ::Logbuch::Tracing.__wrap_methods
        end

        {% unless @type.module? %}
          macro inherited
            ::Logbuch::Tracing.__define_log

            macro finished
              ::Logbuch::Tracing.__wrap_methods
            end
          end
        {% end %}
      {% end %}
    end

    # :nodoc:
    #
    # Defines the log the traced methods of the type it is expanded in write
    # to: whatever `Log` resolves to there, or a log named after the type if
    # that is the stdlib `::Log` class itself. `@[LogType(log: …)]` on
    # the type or an ancestor names another one. It is resolved once per type,
    # so a traced call whose level is disabled costs no allocation.
    macro __define_log
      {% verbatim do %}
        private LOGBUCH_LOG = __logbuch_type_log

        # Resolves the log when it is first used, after every declaration of
        # the type, so an annotation on any of them counts.
        private def self.__logbuch_type_log : ::Log
          {% begin %}
            log = Log
            log = log.is_a?(::Log) ? log : ::Log.for({{ @type.instance.name(generic_args: false).stringify.underscore.gsub(/::/, ".") }})
            {% type_log = ([@type.instance] + @type.instance.ancestors).map(&.annotation(::Logbuch::Annotations::LogType)).find { |anno| anno && anno[:log] } %}
            {% if type_log %}
              ::Logbuch::Tracing.__log_for({{ type_log[:log] }}, log)
            {% else %}
              log
            {% end %}
          {% end %}
        end
      {% end %}
    end

    # :nodoc:
    #
    # Fails the build unless *value*, the `log:` option on *where*, is a
    # constant that holds a log or a source name.
    macro __check_log(value, where)
      {% if value.is_a?(StringLiteral) %}
        {% if value.empty? || value == "." %}
          {% raise "logbuch: log: takes a source name, such as \"shop.checkout\", or one below the type's log, such as \".place\", on #{where.id}" %}
        {% end %}
      {% elsif value.is_a?(Path) %}
        {% resolved = value.resolve? %}
        {% if resolved.nil? %}
          {% raise "logbuch: log: #{value} is not defined, on #{where.id}" %}
        {% elsif resolved.is_a?(TypeNode) %}
          {% raise "logbuch: log: takes a constant that holds a Log or a source name, not the type #{value}, on #{where.id}" %}
        {% elsif %w[StringLiteral StringInterpolation SymbolLiteral NumberLiteral BoolLiteral NilLiteral ArrayLiteral HashLiteral TupleLiteral NamedTupleLiteral RangeLiteral RegexLiteral].includes?(resolved.class_name) %}
          {% raise "logbuch: log: takes a constant that holds a Log, but #{value} is #{resolved}, on #{where.id}" %}
        {% end %}
      {% else %}
        {% raise "logbuch: log: takes a constant that holds a Log, or a source name such as \"shop.checkout\" or \".place\", on #{where.id}" %}
      {% end %}
    end

    # :nodoc:
    #
    # The log that *value*, a `log:` option `__check_log` accepted, names: a
    # source name, one below *base* if it starts with a dot, or the log a
    # constant holds.
    macro __log_for(value, base)
      {% if value.is_a?(StringLiteral) && value.starts_with?(".") %}
        ::Log.for(::Logbuch.__child_source({{ base }}.source, {{ value[1..-1] }}))
      {% elsif value.is_a?(StringLiteral) %}
        ::Log.for({{ value }})
      {% else %}
        ::Logbuch.__log_value({{ value }})
      {% end %}
    end

    # :nodoc:
    #
    # Fails the build unless *value*, the `lock:` option on *where*, is an
    # expression that can name a lock: an instance or class variable, a
    # constant or a call, such as `@lock`, `@@lock`, `LOCK` or `lock`. A
    # `@[Logged]` and a `@[LogType]` take the same ones. A name such as
    # `lock` is parsed as a variable where a local variable of that name is
    # in scope, such as at the top level; in the method that takes the lock,
    # it is the call again.
    macro __check_lock(value, where)
      {% unless value.is_a?(InstanceVar) || value.is_a?(ClassVar) || value.is_a?(Call) || value.is_a?(Var) || value.is_a?(Path) %}
        {% raise "logbuch: lock: takes the lock to hold while converting, such as lock: @lock, on #{where.id}" %}
      {% end %}
    end

    # :nodoc:
    #
    # Generates the wrappers for the annotated instance and class methods of
    # the type it is expanded in. The body is emitted verbatim so that its
    # macro code runs in that type, where `@type` is the traced type.
    #
    # With `-Dlogbuch=off`, it checks the annotations the same way but emits
    # no wrappers, so traced methods stay plain methods and an annotation that
    # fails one build fails the other too.
    macro __wrap_methods
      {% verbatim do %}
        {% begin %}
        {% type_log = ([@type] + @type.ancestors).map(&.annotation(::Logbuch::Annotations::LogType)).find { |anno| anno && anno[:log] } %}
        {% if type_log %}
          ::Logbuch::Tracing.__check_log({{ type_log[:log] }}, {{ "@[LogType] of #{@type.name(generic_args: false)}" }})
          # Typing the log here fails the build for a constant that holds no
          # log, even when no traced method is called or tracing is off.
          {% if type_log[:log].is_a?(Path) %}
            typeof(LOGBUCH_LOG)
          {% end %}
        {% end %}
        {% methods = @type.methods.map { |method| {method, false} } + @type.class.methods.map { |method| {method, true} } %}
        {% for pair, method_index in methods %}
          {% method = pair[0] %}
          {% class_method = pair[1] %}
          {% label = "#{@type.name(generic_args: false)}#{class_method ? ".".id : "#".id}#{method.name}" %}
          # `@[LogAs]` belongs on parameters and fields; a method is traced
          # with `@[Logged]`, which takes the method's detail.
          {% if method.annotation(::Logbuch::Annotations::LogAs) %}
            {% raise "logbuch: @[LogAs] goes on parameters and fields; trace #{label.id} with @[Logged] and give it the detail, such as @[Logged(:full)]" %}
          {% end %}
          {% traces = method.annotations(::Logbuch::Annotations::Logged) %}
          {% error_annos = method.annotations(::Logbuch::Annotations::LogError) %}
          {% accept_annos = method.annotations(::Logbuch::Annotations::LogAccept) %}
          {% if traces.size > 1 %}
            {% raise "logbuch: #{label.id} has more than one @[Logged]" %}
          {% end %}
          # `@[LogError]` or `@[LogAccept]` traces a method too, as a
          # `@[Logged]` without arguments would.
          {% traced = traces.size == 1 || !(error_annos.empty? && accept_annos.empty?) %}
          {% if traced && method.abstract? %}
            {% raise "logbuch: cannot trace abstract method #{label.id}; trace the implementations instead" %}
          {% end %}
          # The compiler copies an annotation on `initialize` to the `new` it
          # generates, so tracing it would trace `new` instead.
          {% if traced && method.name == "initialize" %}
            {% raise "logbuch: cannot trace #{label.id}; trace a method that creates the object instead" %}
          {% end %}
          # `with … yield` sets the receiver of the caller's block, which the
          # wrapper's forwarding block cannot pass on. The literals in the
          # body's text are blanked first, so the words inside one do not
          # count. `stringify` writes them in four forms, whatever their
          # source: `"…"` for a string, a heredoc or a quoted symbol, also
          # one written as `%q()`, `%()` or `%Q()`; `` `…` `` for a command;
          # `'…'` for a char; and `/…/` for a regex. Matched from the left, a
          # `"` in a char starts no string. A regex starts at a `/` that no
          # space follows, as one does in a division, and that no `:` or `.`
          # precedes, as in `:/` or `&./(2)`. An interpolation is blanked
          # with the literal around it; `code` matches its code, with the
          # literals and braces in it, so a `"` or a `}` in there does not
          # end that literal early.
          {% if traced && method.accepts_block? && method.body.stringify.gsub(/(?<literal>"(?:[^"\\#]|\\.|\#(?!\{)|\#\{(?&code)\})*+"|`(?:[^`\\#]|\\.|\#(?!\{)|\#\{(?&code)\})*+`|'(?:[^'\\]|\\.[^']*)'|(?<![:.])\/(?!\s)(?:[^\/\\#\n]|\\.|\#(?!\{)|\#\{(?&code)\})*+\/)(?(DEFINE)(?<code>(?:(?&literal)|\{(?&code)\}|[^{}])*+))/, "\"\"") =~ /(^|\W)with\s.+\syield\b/ %}
            {% raise "logbuch: #{label.id} uses `with … yield`, which a traced method cannot forward; remove @[Logged] or yield without `with`" %}
          {% end %}
          # Crystal adds a redefinition of a method whose typed splat is
          # followed by a named parameter without a default as an overload
          # instead of replacing the method (1.22.0), so the original would
          # keep answering every call and the trace would be silently lost.
          {% if traced && method.splat_index && !method.args[method.splat_index].restriction.is_a?(Nop) %}
            {% splat = method.args[method.splat_index] %}
            {% required = method.args[(method.splat_index + 1)..-1].find(&.default_value.is_a?(Nop)) %}
            {% if required %}
              {% raise "logbuch: cannot trace #{label.id}: Crystal adds a redefinition of a method whose typed splat *#{splat.internal_name} is followed by the required named parameter #{required.name} as an overload instead of replacing the method, so the trace would be lost; give #{required.name} a default value or drop the splat's type restriction" %}
            {% end %}
          {% end %}
          {% if traced %}
            {% anno = traces[0] %}
            # The positional arguments are told apart by what they are: the
            # description string, a level and a detail. A level or a detail is
            # a symbol or a `Log::Severity` or `Logbuch::Detail` path, the
            # forms `LEVEL_NAMES` and `DETAIL_NAMES` list, as everywhere else
            # an annotation takes one.
            {% description = nil %}
            {% severity = nil %}
            {% detail = nil %}
            {% for arg in (anno ? anno.args : [] of ASTNode) %}
              {% kind = nil %}
              {% value = nil %}
              {% form = (arg.is_a?(SymbolLiteral) || arg.is_a?(Path)) ? arg.stringify.gsub(/^::/, "") : "" %}
              {% if arg.is_a?(StringLiteral) && !arg.empty? %}
                {% kind = "description" %}
                {% value = arg %}
              {% elsif ::Logbuch::LEVEL_NAMES[form] %}
                {% kind = "level" %}
                {% value = ::Logbuch::LEVEL_NAMES[form] %}
              {% elsif ::Logbuch::DETAIL_NAMES[form] %}
                {% kind = "detail" %}
                {% value = ::Logbuch::DETAIL_NAMES[form] %}
              {% elsif arg.is_a?(SymbolLiteral) && arg.id.stringify == "redacted" %}
                {% raise "logbuch: :redacted goes on parameters and fields with @[LogAs(:redacted)], not on #{label.id}" %}
              {% else %}
                {% raise "logbuch: @[Logged] takes a description string, a level (:trace, :debug, :info, :notice, :warn, :error or :fatal) and a detail (:omit, :id, :summary or :full), not #{arg}, on #{label.id}" %}
              {% end %}
              {% if (kind == "description" && description) || (kind == "level" && severity) || (kind == "detail" && detail) %}
                {% raise "logbuch: @[Logged] takes one #{kind.id}, on #{label.id}" %}
              {% end %}
              {% if kind == "description" %}{% description = value %}{% end %}
              {% if kind == "level" %}{% severity = value %}{% end %}
              {% if kind == "detail" %}{% detail = value %}{% end %}
            {% end %}
            {% severity = severity || "trace" %}
            {% detail = detail || "Summary" %}
            # The options that became annotations or positional arguments say
            # where they went.
            {% moved = {"allow" => "@[LogAccept(...)]", "stacktrace" => "@[LogError(..., stacktrace: false)]", "level" => "a positional level, such as @[Logged(:debug)]", "detail" => "a positional detail, such as @[Logged(:full)]"} %}
            {% for key in (anno ? anno.named_args.keys : [] of ASTNode) %}
              {% if moved[key.stringify] %}
                {% raise "logbuch: #{key}: is not an option of @[Logged]; use #{moved[key.stringify].id} on #{label.id}" %}
              {% end %}
              {% unless %w[lock log result slow timing].includes?(key.stringify) %}
                {% raise "logbuch: unknown option #{key} on #{label.id}; use lock:, log:, result:, slow: or timing:" %}
              {% end %}
            {% end %}
            # `log: "shop.export"` writes the method's lines to that source,
            # `log: ".export"` to one below the type's log, and `log: AUDIT_LOG`
            # to the log the constant holds.
            {% log_arg = anno && anno[:log] %}
            {% if log_arg %}
              ::Logbuch::Tracing.__check_log({{ log_arg }}, {{ label }})
            {% end %}
            {% with_result = detail != "Omit" && !%w[Nil ::Nil Void ::Void].includes?(method.return_type.stringify) %}
            {% result_converter = anno && anno[:result] %}
            {% if result_converter %}
              {% unless result_converter.is_a?(ProcLiteral) && result_converter.args.size == 1 %}
                {% raise "logbuch: result: takes a block in arrow notation with one parameter, such as ->(jobs) { jobs.size }, on #{label.id}" %}
              {% end %}
              {% unless with_result %}
                {% raise "logbuch: result: has no effect on #{label.id}, which logs no result" %}
              {% end %}
            {% end %}
            # `@[LogError(IO::Error, :warn, stacktrace: false)]` and
            # `@[LogAccept(KeyError, :info)]` each become cases of one list:
            # `{type, accepted, level or nil, stacktrace or nil}`. The typed
            # cases are sorted so a subclass, which has more ancestors, comes
            # before its superclass, and the most specific type wins; a
            # `LogError` without types is the case for every other exception.
            {% cases = [] of ASTNode %}
            {% fallback = nil %}
            {% seen_types = [] of ASTNode %}
            {% for pair in error_annos.map { |error_anno| {error_anno, false} } + accept_annos.map { |accept_anno| {accept_anno, true} } %}
              {% case_anno = pair[0] %}
              {% accepted = pair[1] %}
              {% name = accepted ? "LogAccept" : "LogError" %}
              {% case_types = [] of ASTNode %}
              {% case_level = nil %}
              {% for arg in case_anno.args %}
                {% form = (arg.is_a?(SymbolLiteral) || arg.is_a?(Path)) ? arg.stringify.gsub(/^::/, "") : "" %}
                {% if ::Logbuch::LEVEL_NAMES[form] && !case_level %}
                  {% case_level = ::Logbuch::LEVEL_NAMES[form] %}
                {% elsif arg.is_a?(Path) && arg.resolve? && arg.resolve.is_a?(TypeNode) && arg.resolve <= ::Exception %}
                  {% case_types << arg %}
                {% else %}
                  {% raise "logbuch: @[#{name.id}] takes exception types and one level, such as @[#{name.id}(IO::Error, KeyError, :warn)], not #{arg}, on #{label.id}" %}
                {% end %}
              {% end %}
              {% for key in case_anno.named_args.keys %}
                {% unless key.stringify == "stacktrace" && case_anno[:stacktrace].is_a?(BoolLiteral) %}
                  {% raise "logbuch: @[#{name.id}] takes only stacktrace: true or false, on #{label.id}" %}
                {% end %}
              {% end %}
              {% case_stacktrace = case_anno[:stacktrace] %}
              {% if case_types.empty? %}
                {% if accepted %}
                  {% raise "logbuch: @[LogAccept] takes at least one exception type, on #{label.id}" %}
                {% end %}
                {% if fallback %}
                  {% raise "logbuch: #{label.id} has more than one @[LogError] without types" %}
                {% end %}
                {% fallback = {nil, false, case_level, case_stacktrace} %}
              {% end %}
              {% for type in case_types %}
                {% if seen_types.any? { |seen| seen.resolve == type.resolve } %}
                  {% raise "logbuch: #{type} is listed more than once in the @[LogError] and @[LogAccept] annotations of #{label.id}" %}
                {% end %}
                {% seen_types << type %}
                {% cases << {type, accepted, case_level, case_stacktrace} %}
              {% end %}
            {% end %}
            {% cases = cases.sort_by { |entry| -entry[0].resolve.ancestors.size } %}
            {% error_level = fallback && fallback[2] ? fallback[2] : "error" %}
            {% error_stacktrace = fallback ? fallback[3] : nil %}
            # `lock: @lock` converts the arguments and the result while holding
            # the lock, so a value other threads change is read under it.
            {% lock_arg = anno && anno[:lock] %}
            {% unless lock_arg.nil? %}
              ::Logbuch::Tracing.__check_lock({{ lock_arg }}, {{ label }})
            {% end %}
            {% lock_open = lock_arg ? "::Logbuch.__locked_data(#{lock_arg}) { ".id : "".id %}
            {% lock_close = lock_arg ? " }".id : "".id %}
            {% timing_arg = anno && anno[:timing] %}
            {% unless timing_arg.nil? || timing_arg.is_a?(BoolLiteral) %}
              {% raise "logbuch: timing: must be true or false on #{label.id}" %}
            {% end %}
            # `slow: {ms: 200, level: :error}` writes the exit line of a call
            # that took at least 200 ms at `:error`; `level:` defaults to `:warn`.
            # With `args: true`, a slow exit line also carries the arguments
            # when the entry line was not written.
            {% ranks = {"trace" => 0, "debug" => 1, "info" => 2, "notice" => 3, "warn" => 4, "error" => 5, "fatal" => 6} %}
            {% slow_arg = anno && anno[:slow] %}
            {% slow_severity = "warn" %}
            {% slow_args = false %}
            {% if slow_arg %}
              {% unless slow_arg.is_a?(NamedTupleLiteral) && slow_arg[:ms].is_a?(NumberLiteral) && slow_arg[:ms] >= 0 && slow_arg.keys.all? { |key| %w[ms level args].includes?(key.stringify) } %}
                {% raise "logbuch: slow: takes a named tuple such as {ms: 200, level: :warn}, on #{label.id}" %}
              {% end %}
              {% unless slow_arg[:args].nil? || slow_arg[:args].is_a?(BoolLiteral) %}
                {% raise "logbuch: slow: args: must be true or false on #{label.id}" %}
              {% end %}
              {% slow_args = slow_arg[:args] == true %}
              {% slow_level_arg = slow_arg[:level] %}
              {% unless slow_level_arg.nil? %}
                {% form = (slow_level_arg.is_a?(SymbolLiteral) || slow_level_arg.is_a?(Path)) ? slow_level_arg.stringify.gsub(/^::/, "") : "" %}
                {% slow_severity = ::Logbuch::LEVEL_NAMES[form] %}
                {% unless slow_severity %}
                  {% raise "logbuch: invalid slow: level #{slow_level_arg} on #{label.id}" %}
                {% end %}
              {% end %}
              # A slow call's exit line must stand out, so a `slow:` level at
              # or below the method's level is a mistake.
              {% if ranks[slow_severity] <= ranks[severity] %}
                {% raise "logbuch: slow: level :#{slow_severity.id} must be above the method's level :#{severity.id}, on #{label.id}" %}
              {% end %}
              {% if timing_arg == false %}
                {% raise "logbuch: slow: needs timing, so it takes no timing: false, on #{label.id}" %}
              {% end %}
            {% end %}
            # With `-Dlogbuch_timing=off`, no clock is read, so no call is known
            # to be slow.
            {% timing = !%w[off 0].includes?(flag?(:logbuch_timing)) && timing_arg != false %}
            {% slow_check = slow_arg && timing %}
            # A call is slow from this many nanoseconds on, counted here, so
            # an exit line compares two numbers and builds no `Time::Span`. A
            # fractional `ms:` rounds to the nanosecond, as `Float#milliseconds`
            # does.
            {% if slow_check %}
              {% slow_ms = slow_arg[:ms] %}
              {% slow_ns = [:f32, :f64].includes?(slow_ms.kind) ? (1_000_000.0 * slow_ms + 0.5) // 1 : 1_000_000_u64 * slow_ms %}
            {% end %}
            # The highest level the call's entry and exit lines may use: the
            # method's, a slow call's, or an accepted exception's.
            {% gate_severity = slow_check ? slow_severity : severity %}
            {% for entry in cases %}
              {% if entry[1] && entry[2] && ranks[entry[2]] > ranks[gate_severity] %}
                {% gate_severity = entry[2] %}
              {% end %}
            {% end %}
            {% captured_block = method.block_arg && !method.block_arg.name.stringify.empty? %}

            {% params = [] of String %}
            {% limit_checks = [] of ASTNode %}
            {% param_names = [] of String %}
            {% call = [] of String %}
            {% named = [] of String %}
            {% data = [] of String %}
            {% arguments = method.args.map_with_index { |arg, index| {arg, index} } %}
            {% if method.double_splat %}{% arguments << {method.double_splat, -1} %}{% end %}
            {% for pair in arguments %}
              {% arg = pair[0] %}
              {% index = pair[1] %}
              {% if arg.annotation(::Logbuch::Annotations::Logged) %}
                {% raise "logbuch: @[Logged] goes on methods; use @[LogAs] on parameter #{arg.internal_name} of #{label.id}" %}
              {% end %}
              {% where = "parameter #{arg.internal_name} of #{label.id}" %}
              {% arg_annos = arg.annotations(::Logbuch::Annotations::LogAs) %}
              {% if arg_annos.size > 1 %}
                {% raise "logbuch: #{where.id} has more than one @[LogAs]" %}
              {% end %}
              {% marker = arg_annos[0] %}
              {% arg_detail = detail %}
              {% if marker %}
                ::Logbuch.__check_log_as({{ marker.args.empty? ? nil : marker.args }}, {{ marker.named_args.empty? ? nil : marker.named_args }}, {{ where }})
                # Without a detail, `:redacted` keeps the method's detail.
                {% marker_detail = marker.args.map { |marker_arg| ::Logbuch::DETAIL_NAMES[marker_arg.stringify.gsub(/^::/, "")] }.find { |name| name } %}
                {% arg_detail = marker_detail || detail %}
                # A splat is logged as a tuple and a double splat as a named
                # tuple. Any other parameter is checked against its type when
                # that names one type here: not a union, not a free variable
                # and not one of the type's own type variables, at the detail
                # it is logged at. A converter's result is what the limits
                # apply to. The check runs in the method that checks the
                # messages below, where the fields of that type are known.
                {% rule = marker.args.find { |marker_arg| marker_arg.is_a?(Call) && marker_arg.name.stringify == "items" } %}
                {% if (marker[:cap] || marker[:length] || rule) && !marker[:converter] %}
                  {% limit_type = nil %}
                  {% restriction = arg.restriction %}
                  {% if index == -1 %}
                    {% limit_type = "::NamedTuple" %}
                  {% elsif index == method.splat_index %}
                    {% limit_type = "::Tuple" %}
                  {% elsif (restriction.is_a?(Path) || restriction.is_a?(Generic)) && !(method.free_vars || [] of MacroId).map(&.stringify).includes?(restriction.stringify) && !@type.type_vars.map(&.stringify).includes?(restriction.stringify) %}
                    {% resolved = restriction.resolve? %}
                    {% if resolved.is_a?(TypeNode) && !resolved.union? %}
                      {% limit_type = "::#{resolved}" %}
                    {% end %}
                  {% end %}
                  {% limit_checks << {limit_type, marker.named_args.empty? ? nil : marker.named_args, where, arg_detail, rule} %}
                {% end %}
              {% end %}
              {% logged = arg_detail != "Omit" && !arg.internal_name.stringify.empty? %}
              {% unless arg.internal_name.stringify.empty? %}
                {% param_names << arg.internal_name.stringify %}
              {% end %}
              {% if index == -1 %}
                {% params << "**#{arg.internal_name}" + (arg.restriction.is_a?(Nop) ? "" : " : #{arg.restriction}") %}
                {% call << "**#{arg.internal_name}" %}
              {% elsif index == method.splat_index %}
                {% params << "*#{arg.internal_name}" + (arg.restriction.is_a?(Nop) ? "" : " : #{arg.restriction}") %}
                {% unless arg.internal_name.stringify.empty? %}
                  {% call << "*#{arg.internal_name}" %}
                {% end %}
              {% elsif method.splat_index && index > method.splat_index %}
                {% params << arg.stringify %}
                {% named << "#{arg.name}: #{arg.internal_name}" %}
              {% else %}
                {% params << arg.stringify %}
                {% call << arg.internal_name.stringify %}
              {% end %}
              {% if logged %}
                {% data << {arg.internal_name.stringify, arg_detail, marker} %}
              {% end %}
            {% end %}
            {% call = call + named %}
            {% if slow_args && data.empty? %}
              {% raise "logbuch: slow: args: has no effect on #{label.id}, which logs no arguments" %}
            {% end %}
            # Each argument converts as its `@[LogAs]` says, through
            # `Logbuch.__convert_as`.
            {% args_value = "#{lock_open}::Log::Metadata::Value.new({" + data.map { |entry| "#{entry[0].stringify.id} => ::Logbuch.__convert_as(#{entry[0].id}, #{entry[2] && !entry[2].args.empty? ? entry[2].args : "nil".id}, #{entry[2] && !entry[2].named_args.empty? ? entry[2].named_args : "nil".id}, detail: ::Logbuch::Detail::#{entry[1].id})" }.join(", ") + "})#{lock_close}" %}
            {% if captured_block %}
              {% params << "&#{method.block_arg}" %}
              {% call << "&#{method.block_arg.internal_name}" %}
            {% elsif method.accepts_block? %}
              {% params << "&" %}
            {% end %}

            # The check fails the build for a message that is not a `String`.
            # The wrapper types it, so a call typed first meets it there, and
            # so does the type's body below, which is typed whether or not
            # the method is called, and with tracing off too. Its name carries
            # the type, so the check of a subclass or an including type does
            # not override this one.
            {% facts = {type: @type.name(generic_args: false).stringify, method: method.name.stringify, class_method: class_method, label: label, description: description, level: severity, params: param_names.empty? ? "[] of ::String".id : param_names} %}
            {% check = "__logbuch_check_#{@type.name(generic_args: false).stringify.underscore.gsub(/::/, "_").id}_#{method_index}".id %}
            {% for receiver in (class_method ? ["self."] : ["", "self."]) %}
              private def {{ receiver.id }}{{ check }}(entry : E, exit : X, error : R) : Nil forall E, X, R
                \{% for converter in [{"entry_message", E}, {"exit_message", X}, {"error_message", R}] %}
                  \{% unless converter[1] == ::String %}
                    \{% raise "logbuch: the #{converter[0].id} converter must expand to a String, not #{converter[1]}, on {{ label.id }}" %}
                  \{% end %}
                \{% end %}
              end
            {% end %}

            # Only typed, never called, so a `log:` constant that holds no
            # log, a message converter that does not expand to a `String`, or
            # a limit on a parameter that cannot change how it is logged,
            # fails every build. The type's body cannot call the converters
            # itself: called from this hook, the compiler takes them for
            # macros defined after the call. In a method, they expand when it
            # is typed, and the limit checks see the fields of every type.
            private def self.{{ check }} : Nil
              {% for limit_check in limit_checks %}
                ::Logbuch.__check_limit_target({{ limit_check[0] }}, {{ limit_check[1] }}, {{ limit_check[2] }}, {{ limit_check[3] }}, false, {{ limit_check[4] }})
              {% end %}
              {{ check }}(::Logbuch::Messages.entry_message({{ facts }}), ::Logbuch::Messages.exit_message({{ facts }}), ::Logbuch::Messages.error_message({{ facts }}))
              {% if log_arg.is_a?(Path) %}
                ::Logbuch::Tracing.__log_for({{ log_arg }}, LOGBUCH_LOG)
              {% end %}
            end

            typeof({{ check }})

            {% unless %w[off 0].includes?(flag?(:logbuch)) %}
            {% if log_arg %}
              private LOGBUCH_LOG_{{ method_index }} = ::Logbuch::Tracing.__log_for({{ log_arg }}, LOGBUCH_LOG)
            {% end %}
            # The messages are constants, so a converter cannot refer to the
            # call's values, and a string literal costs what the literal does.
            private LOGBUCH_ENTRY_{{ method_index }} = ::Logbuch::Messages.entry_message({{ facts }})
            private LOGBUCH_EXIT_{{ method_index }} = ::Logbuch::Messages.exit_message({{ facts }})
            private LOGBUCH_ERROR_{{ method_index }} = ::Logbuch::Messages.error_message({{ facts }})

            # The method's other annotations, such as `@[Deprecated]`, carry over
            # to the wrapper, which is what callers now call. logbuch's own
            # stay on the original, so the method is not seen as traced twice.
            {% for other in method.annotations %}
              {% unless [::Logbuch::Annotations::Logged, ::Logbuch::Annotations::LogError, ::Logbuch::Annotations::LogAccept].includes?(other.name.resolve) %}
                {{ other }}
              {% end %}
            {% end %}
            {% yielding = method.accepts_block? && !captured_block %}
            {% level = "::Log::Severity::#{severity.capitalize.id}".id %}
            {% slow_level = "::Log::Severity::#{slow_severity.capitalize.id}".id %}
            # A call writes its entry and exit lines when the highest level
            # they may use is enabled; error lines check their own level. When
            # that level is above the method's, from `slow:` or an accepted
            # exception's level, each line checks its own level before its
            # data is converted, so a fast call converts nothing. A line that
            # always uses the highest level needs no check of its own; if the
            # level changes during the call, `Logbuch.__line` still drops it.
            {% gate_level = "::Log::Severity::#{gate_severity.capitalize.id}".id %}
            {% below_gate = gate_severity != severity %}
            {{ method.visibility.id == "public" ? "".id : method.visibility.id }} def {{ class_method ? "self.".id : "".id }}{{ method.name }}({{ params.join(", ").id }}){% if method.return_type %} : {{ method.return_type }}{% end %}{% if method.free_vars && !method.free_vars.empty? %} forall {{ method.free_vars.splat }}{% end %}
              typeof({{ check }}(LOGBUCH_ENTRY_{{ method_index }}, LOGBUCH_EXIT_{{ method_index }}, LOGBUCH_ERROR_{{ method_index }}))
              %log = {% if log_arg %}LOGBUCH_LOG_{{ method_index }}{% else %}LOGBUCH_LOG{% end %}
              %fiber = ::Fiber.current
              %outer = %fiber.__logbuch_call
              # Called on `self`, not passed, so a struct is not copied.
              %receiver = self.__logbuch_receiver
              # A call whose levels are all disabled writes no lines but its
              # error line. One that a traced override makes through `super`
              # writes none, since the override's lines cover it. That is
              # asked only once the levels let the call write a line, so a
              # disabled call skips it; nil means it was not asked, and an
              # error line asks it then. All these calls share the one
              # forwarded call below, so a yielding method, which is inlined
              # into every call site, is copied there once.
              %super = nil
              %on = %log.level <= {{ gate_level }} && !(%super = ::Logbuch.__super_call?(%outer, %receiver, {{ method.name.stringify }}, {{ label }}))
              {% if below_gate %}
                %entered = %on && %log.level <= {{ level }}
              {% end %}
              if {% if below_gate %}%entered{% else %}%on{% end %}
                ::Logbuch.__line(%log, severity: {{ level }}, message: LOGBUCH_ENTRY_{{ method_index }}, method: {{ label }}, entries: ::NamedTuple.new{% unless data.empty? %}, args: {{ args_value.id }}{% end %})
              end
              # Calls this one reaches through `super` see the note and stay
              # silent, whether or not this one writes lines.
              %fiber.__logbuch_call = ::Tuple.new(%receiver, {{ method.name.stringify }}, {{ label }})
              # The clock covers the method only, not writing the lines or
              # converting the result, and is read only by a call that writes
              # lines.
              {% if timing %}%started = (::Time.instant if %on){% end %}
              {% if yielding %}
                # The caller's block can leave this method with `break` or
                # `return`; the `ensure` below then writes the exit line.
                %settled = false
              {% end %}
              begin
                {% if yielding %}
                  %result = previous_def({{ call.join(", ").id }}) { |*%args| yield *%args }
                {% else %}
                  %result = previous_def({{ call.join(", ").id }})
                {% end %}
                {% if timing %}%elapsed = %started ? %started.elapsed : ::Time::Span.zero{% end %}
                {% if yielding %}%settled = true{% end %}
              rescue %error
                {% if timing %}%elapsed = %started ? %started.elapsed : ::Time::Span.zero{% end %}
                {% if yielding %}%settled = true{% end %}
                %super = ::Logbuch.__super_call?(%outer, %receiver, {{ method.name.stringify }}, {{ label }}) if %super.nil?
                # An accepted exception ends the call like a result, on the exit
                # line. Errors are logged at their level even when the method's
                # level is disabled; a call made through `super` leaves its
                # error to the override.
                {% unless cases.empty? %}
                case %error
                {% end %}
                {% for entry in cases %}
                when {{ entry[0] }}
                  {% if entry[1] %}
                    {% accept_severity = entry[2] || severity %}
                    {% accept_level = "::Log::Severity::#{accept_severity.capitalize.id}".id %}
                    {% accept_check = accept_severity != gate_severity %}
                    if %on
                      {% if slow_check %}%slow = ::Logbuch.__nanoseconds(%elapsed) >= {{ slow_ns }}{% end %}
                      {% if accept_check %}
                      %severity = {% if slow_check && ranks[slow_severity] > ranks[accept_severity] %}(%slow ? {{ slow_level }} : {{ accept_level }}){% else %}{{ accept_level }}{% end %}
                      if %log.level <= %severity
                      {% end %}
                        %written = ::Logbuch.__line(%log, severity: {% if accept_check %}%severity{% else %}{{ accept_level }}{% end %}, message: LOGBUCH_EXIT_{{ method_index }}, method: {{ label }}, entries: {
                          result: ::Logbuch.__convert(%error, ::Logbuch::Detail::Summary),
                          {% if timing %}duration_ns: ::Logbuch.__nanoseconds(%elapsed),{% end %}
                        }, exception: {% if entry[3] == true %}%error{% else %}nil{% end %}{% if slow_args && slow_check %}, args: ({{ args_value.id }} unless %entered){% end %}{% if slow_check %}, slow: %slow{% end %})
                        # Logged in full here, so the traced calls it passes
                        # through after this one log only its type, unless
                        # the backend lost the line.
                        %error.__logbuch_logged = true if %written
                      {% if accept_check %}
                      end
                      {% end %}
                    end
                  {% else %}
                    ::Logbuch.__error(%log, message: LOGBUCH_ERROR_{{ method_index }}, method: {{ label }}, error: %error, duration: {% if timing %}(::Logbuch.__nanoseconds(%elapsed) if %on){% else %}nil{% end %}, severity: ::Log::Severity::{{ (entry[2] || "error").capitalize.id }}, stacktrace: {{ entry[3] }}) unless %super
                  {% end %}
                {% end %}
                {% unless cases.empty? %}
                else
                {% end %}
                  ::Logbuch.__error(%log, message: LOGBUCH_ERROR_{{ method_index }}, method: {{ label }}, error: %error, duration: {% if timing %}(::Logbuch.__nanoseconds(%elapsed) if %on){% else %}nil{% end %}, severity: ::Log::Severity::{{ error_level.capitalize.id }}, stacktrace: {{ error_stacktrace }}) unless %super
                {% unless cases.empty? %}
                end
                {% end %}
                raise %error
              ensure
                %fiber.__logbuch_call = %outer
                {% if yielding %}
                  if %on && !%settled
                    {% if timing %}%left = %started ? %started.elapsed : ::Time::Span.zero{% end %}
                    {% if slow_check %}%slow = ::Logbuch.__nanoseconds(%left) >= {{ slow_ns }}{% end %}
                    {% if below_gate %}
                    %severity = {% if slow_check %}(%slow ? {{ slow_level }} : {{ level }}){% else %}{{ level }}{% end %}
                    if %log.level <= %severity
                    {% end %}
                      ::Logbuch.__line(%log, severity: {% if below_gate %}%severity{% else %}{{ level }}{% end %}, message: LOGBUCH_EXIT_{{ method_index }}, method: {{ label }}, entries: {% if timing %}{
                        duration_ns: ::Logbuch.__nanoseconds(%left),
                      }{% else %}::NamedTuple.new{% end %}{% if slow_args && slow_check %}, args: ({{ args_value.id }} unless %entered){% end %}{% if slow_check %}, slow: %slow{% end %})
                    {% if below_gate %}
                    end
                    {% end %}
                  end
                {% end %}
              end
              if %on
                {% if slow_check %}%slow = ::Logbuch.__nanoseconds(%elapsed) >= {{ slow_ns }}{% end %}
                {% if below_gate %}
                %severity = {% if slow_check %}(%slow ? {{ slow_level }} : {{ level }}){% else %}{{ level }}{% end %}
                if %log.level <= %severity
                {% end %}
                  ::Logbuch.__line(%log, severity: {% if below_gate %}%severity{% else %}{{ level }}{% end %}, message: LOGBUCH_EXIT_{{ method_index }}, method: {{ label }}, entries: {% if with_result || timing %}{
                    {% if with_result %}result: {{ lock_open }}{% if result_converter %}::Logbuch.__convert(%result, ::Logbuch::Detail::{{ detail.id }}) { |{{ result_converter.args[0].name }}| {{ result_converter.body }} }{% else %}::Logbuch.__convert(%result, ::Logbuch::Detail::{{ detail.id }}){% end %}{{ lock_close }},{% end %}
                    {% if timing %}duration_ns: ::Logbuch.__nanoseconds(%elapsed),{% end %}
                  }{% else %}::NamedTuple.new{% end %}{% if slow_args && slow_check %}, args: ({{ args_value.id }} unless %entered){% end %}{% if slow_check %}, slow: %slow{% end %})
                {% if below_gate %}
                end
                {% end %}
              end
              %result
            end
            {% end %}

          {% end %}
        {% end %}
        {% end %}
      {% end %}
    end
  end
end

# A class, struct or module with a traced method that does not include
# `Logbuch::Tracing` gets the include here, so annotating a method is enough.
# Every type defined in the program is checked: the namespaces from the top
# level, plus every class and struct, which also finds private ones. A private
# type, or one inside a private type, cannot be reopened from here: `::Name`
# does not resolve to it, and reopening it would define a new, empty type. It
# fails the build instead, and so does an enum, whose body takes no `include`.
# Generic instances among the subclasses, such as `Pointer(UInt8)`, are
# skipped: asking one for its constants crashes released compilers up to at
# least 1.22.0 (https://github.com/crystal-lang/crystal/issues/5757), and its
# generic type is checked anyway.
#
# Two kinds of type stay hidden from this check, so their traced methods are
# not traced unless the type includes `Logbuch::Annotations` itself: a private
# top-level module, with the modules inside it, which neither the top-level
# constants nor the subclasses list, and a type that another `macro finished`
# defines after this one has run.
#
# The same walk checks the annotations of every type it sees, whether logbuch
# traces the type, converts it or neither, and in every build: the type's
# `@[LogType]`, and the annotations of the untraced methods, those without
# `@[Logged]`, `@[LogError]` or `@[LogAccept]`, and of their parameters. `Logbuch::Tracing.__wrap_methods` checks the traced
# methods, which need the type's scope to resolve the names in their
# annotations, and `Logbuch.__check_fields` the fields, whose instance
# variables are not known yet here.
macro finished
  {% types = @top_level.constants.map { |name| @top_level.constant(name) } + Object.all_subclasses.select { |type| type.instance == type && type.type_vars.all?(&.is_a?(MacroId)) } %}
  {% seen = {} of String => Bool %}
  {% for type in types %}
    {% if type.is_a?(TypeNode) && (type.class? || type.struct? || type.module? || type < ::Enum) && !seen[type.stringify] %}
      {% seen[type.stringify] = true %}
      {% type_name = type.name(generic_args: false) %}
      # Exceptions are converted by `Exception#to_trace`, so `stacktrace:` is
      # the only option they read besides `log:` and `lock:`. A `log:`
      # constant is resolved in the traced type that uses it, which checks
      # it there.
      {% for anno in type.annotations(::Logbuch::Annotations::LogType) %}
        {% unless anno[:stacktrace].nil? %}
          {% unless type <= ::Exception %}
            {% raise "logbuch: stacktrace: goes on the @[LogType] of an exception class, not on #{type_name}" %}
          {% end %}
          {% unless anno[:stacktrace].is_a?(BoolLiteral) %}
            {% raise "logbuch: stacktrace: takes true or false, on @[LogType] of #{type_name}" %}
          {% end %}
        {% end %}
        {% unless anno.args.empty? && anno.named_args.keys.all? { |key| %w[lock log inspect stacktrace].includes?(key.stringify) } %}
          {% raise "logbuch: @[LogType] takes only lock:, log: and inspect:, and stacktrace: on an exception class, such as @[LogType(lock: @lock)], on #{type_name}" %}
        {% end %}
        {% unless anno[:lock].nil? %}
          ::Logbuch::Tracing.__check_lock({{ anno[:lock] }}, {{ "@[LogType] of #{type_name}" }})
        {% end %}
        # `inspect:` sets the detail of the `inspect` logbuch gives the
        # type, which its own `inspect` or an ancestor's replaces.
        {% unless anno[:inspect].nil? %}
          {% unless anno[:inspect].is_a?(SymbolLiteral) && %w[off id summary full].includes?(anno[:inspect].id.stringify) %}
            {% raise "logbuch: inspect: takes :off, :id, :summary or :full, on @[LogType] of #{type_name}" %}
          {% end %}
          {% if ([type] + type.ancestors).any? { |base| !%w[Reference Struct Object Value].includes?(base.name(generic_args: false).stringify) && base.methods.any? { |method| method.name == "inspect" } } %}
            {% raise "logbuch: inspect: has no effect on #{type_name}, which has an inspect of its own, on @[LogType] of #{type_name}" %}
          {% end %}
        {% end %}
        {% if anno[:log] && !anno[:log].is_a?(Path) %}
          ::Logbuch::Tracing.__check_log({{ anno[:log] }}, {{ "@[LogType] of #{type_name}" }})
        {% end %}
      {% end %}
      # A method without `@[Logged]`, `@[LogError]` or `@[LogAccept]` is not
      # traced, so `@[LogAs]` on its parameters would do nothing.
      {% for pair in type.methods.map { |method| {method, "#"} } + type.class.methods.map { |method| {method, "."} } %}
        {% method = pair[0] %}
        {% if [::Logbuch::Annotations::Logged, ::Logbuch::Annotations::LogError, ::Logbuch::Annotations::LogAccept].all? { |kind| method.annotations(kind).empty? } %}
          {% label = "#{type_name}#{pair[1].id}#{method.name}" %}
          {% if method.annotation(::Logbuch::Annotations::LogAs) %}
            {% raise "logbuch: @[LogAs] goes on parameters and fields; trace #{label.id} with @[Logged] and give it the detail, such as @[Logged(:full)]" %}
          {% end %}
          {% for arg in method.double_splat ? method.args + [method.double_splat] : method.args %}
            {% if arg.annotation(::Logbuch::Annotations::Logged) %}
              {% raise "logbuch: @[Logged] goes on methods; use @[LogAs] on parameter #{arg.internal_name} of #{label.id}" %}
            {% end %}
            {% markers = arg.annotations(::Logbuch::Annotations::LogAs) %}
            {% where = "parameter #{arg.internal_name} of #{label.id}" %}
            {% if markers.size > 1 %}
              {% raise "logbuch: #{where.id} has more than one @[LogAs]" %}
            {% end %}
            {% for marker in markers %}
              ::Logbuch.__check_log_as({{ marker.args.empty? ? nil : marker.args }}, {{ marker.named_args.empty? ? nil : marker.named_args }}, {{ where }})
            {% end %}
          {% end %}
        {% end %}
      {% end %}
      {% unless type.has_constant?("LOGBUCH_LOG") %}
        {% traced_kinds = [::Logbuch::Annotations::Logged, ::Logbuch::Annotations::LogError, ::Logbuch::Annotations::LogAccept] %}
        {% instance_method = type.methods.find { |method| traced_kinds.any? { |kind| method.annotation(kind) } } %}
        {% class_method = type.class.methods.find { |method| traced_kinds.any? { |kind| method.annotation(kind) } } %}
        {% if instance_method || class_method %}
          {% name = type_name %}
          {% if type < ::Enum %}
            {% raise "logbuch: #{name}#{instance_method ? "#".id : ".".id}#{(instance_method || class_method).name} is traced, but Crystal lets no enum include a module, so logbuch cannot trace the methods of the enum #{name}; trace a method of a class, struct or module instead" %}
          {% end %}
          {% if type.private? || parse_type("::#{name}").resolve? != type %}
            {% raise "logbuch: #{name}#{instance_method ? "#".id : ".".id}#{(instance_method || class_method).name} is traced, but logbuch cannot include Logbuch::Tracing into #{type.private? ? "the private type #{name}".id : "#{name}, which is inside a private type".id}; add `include Logbuch::Annotations` to #{name}" %}
          {% end %}
          {{ (type.module? ? "module" : (type.struct? ? "struct" : "class")).id }} ::{{ name }}{% unless type.type_vars.empty? %}({{ type.type_vars.splat }}){% end %}
            include ::Logbuch::Tracing
          end
        {% end %}
      {% end %}
      {% for name in type.constants %}
        {% types << type.constant(name) %}
      {% end %}
    {% end %}
  {% end %}
end
