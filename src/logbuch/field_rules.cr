require "hash"
require "io"
require "log"
require "reference"
require "string"
require "struct"

require "./annotations"
require "./detail"

module Logbuch
  # :nodoc:
  #
  # Yields *value* to the converter of a field, whose result an `inspect`
  # shows. See `__object_to_trace`.
  def self.__inspected(value, &)
    yield value
  end

  # :nodoc:
  #
  # Checks a `@[LogAs]` on a parameter or field: *args* are its positional
  # arguments or nil, *options* its named arguments or nil, and *where* names
  # the parameter or field in the error messages. Parameters and fields share
  # it, so both get the same checks and the same messages. Without a detail,
  # a converter, a limit or an `items(...)` keeps the default detail.
  # Expands to nothing.
  macro __check_log_as(args, options, where)
    {% if args.nil? && options.nil? %}
      {% raise "logbuch: @[LogAs] takes a detail, :omit, :id, :summary or :full, or :redacted, or an option such as converter: or length:, on #{where.id}" %}
    {% end %}
    {% args = [] of ASTNode if args.nil? %}
    # A detail is a symbol or a `Logbuch::Detail` path, the forms
    # `DETAIL_NAMES` lists.
    {% details = [] of String %}
    {% redacted = [] of ASTNode %}
    {% rules = [] of ASTNode %}
    {% for arg in args %}
      {% form = (arg.is_a?(SymbolLiteral) || arg.is_a?(Path)) ? arg.stringify.gsub(/^::/, "") : "" %}
      {% if ::Logbuch::DETAIL_NAMES[form] %}
        {% details << ::Logbuch::DETAIL_NAMES[form] %}
      {% elsif form == ":redacted" %}
        {% redacted << arg %}
      {% elsif arg.is_a?(Call) && arg.name.stringify == "items" && arg.receiver.is_a?(Nop) && arg.block.is_a?(Nop) %}
        {% rules << arg %}
      {% else %}
        {% raise "logbuch: @[LogAs] takes :omit, :id, :summary, :full, :redacted or items(...), not #{arg}, on #{where.id}" %}
      {% end %}
    {% end %}
    {% if details.size > 1 || redacted.size > 1 || rules.size > 1 %}
      {% raise "logbuch: @[LogAs] takes one detail, and :redacted and items(...) at most once, on #{where.id}" %}
    {% end %}
    {% omit = details.size == 1 && details[0] == "Omit" %}
    {% if omit && !redacted.empty? %}
      {% raise "logbuch: @[LogAs] takes :omit or :redacted, not both, on #{where.id}; an omitted value is never logged" %}
    {% end %}
    {% converter = options ? options[:converter] : nil %}
    # `:redacted` logs `"***"`, so a converter next to it would either be
    # ignored or log what `:redacted` promises to hide.
    {% if converter && !redacted.empty? %}
      {% raise "logbuch: @[LogAs] takes :redacted or converter:, not both, on #{where.id}; :redacted always logs \"***\", and a converter that masks the value goes without it" %}
    {% end %}
    {% if options %}
      {% for key in options.keys %}
        {% if %w[level timing].includes?(key.stringify) %}
          {% raise "logbuch: level: and timing: are only allowed on methods, not on #{where.id}" %}
        {% elsif key.stringify == "items" %}
          {% raise "logbuch: unknown option items on #{where.id}; use cap: to limit the items of a collection, or items(...) to set how each item is logged" %}
        {% elsif !%w[converter cap length].includes?(key.stringify) %}
          {% raise "logbuch: unknown option #{key} on #{where.id}; use converter:, cap: or length:, or items(...)" %}
        {% end %}
      {% end %}
    {% end %}
    # The options of the value, then those of its items, each as `{options,
    # how the messages name them}`.
    {% scopes = [{options, ""}] %}
    {% rule = rules[0] %}
    {% if rule %}
      {% rule_options = {} of SymbolLiteral => ASTNode %}
      {% for named in rule.named_args || [] of ASTNode %}
        {% unless %w[converter cap length].includes?(named.name.stringify) %}
          {% raise "logbuch: unknown option #{named.name} in items(...) on #{where.id}; use cap:, length: or converter:" %}
        {% end %}
        {% rule_options[named.name.symbolize] = named.value %}
      {% end %}
      {% if rule.args.size > 1 %}
        {% raise "logbuch: items(...) takes one detail at most, on #{where.id}" %}
      {% end %}
      # An omitted or redacted item would hide what the collection holds;
      # put `:omit` or `:redacted` on the collection instead.
      {% for item_detail in rule.args %}
        {% form = (item_detail.is_a?(SymbolLiteral) || item_detail.is_a?(Path)) ? item_detail.stringify.gsub(/^::/, "") : "" %}
        {% unless ::Logbuch::DETAIL_NAMES[form] && ::Logbuch::DETAIL_NAMES[form] != "Omit" %}
          {% raise "logbuch: items(...) takes :id, :summary or :full, or a Logbuch::Detail member such as Logbuch::Detail::Full, not #{item_detail}, on #{where.id}" %}
        {% end %}
      {% end %}
      {% if rule.args.empty? && rule_options.empty? %}
        {% raise "logbuch: items() sets nothing on #{where.id}; give it a detail, cap:, length: or converter:" %}
      {% end %}
      {% if omit %}
        {% raise "logbuch: items(...) has no effect on :omit, on #{where.id}" %}
      {% end %}
      {% if !redacted.empty? %}
        {% raise "logbuch: items(...) has no effect on :redacted, which logs \"***\", on #{where.id}" %}
      {% end %}
      {% scopes << {rule_options, " in items(...)"} %}
    {% end %}
    {% for scope in scopes %}
      {% scope_options = scope[0] %}
      {% if scope_options %}
        {% if scope_options[:converter] %}
          {% unless scope_options[:converter].is_a?(ProcLiteral) && scope_options[:converter].args.size == 1 %}
            {% raise "logbuch: converter:#{scope[1].id} takes a block in arrow notation with one parameter, such as ->(value) { value.upcase }, on #{where.id}" %}
          {% end %}
          {% if omit %}
            {% raise "logbuch: converter: has no effect on :omit, on #{where.id}" %}
          {% end %}
        {% end %}
        {% for name, value in {cap: scope_options[:cap], length: scope_options[:length]} %}
          {% unless value.nil? %}
            # A float, such as `1e3` or `1.0`, is no integer, whatever its value.
            {% unless value.is_a?(NumberLiteral) && ![:f32, :f64].includes?(value.kind) && value >= 0 %}
              {% raise "logbuch: #{name}:#{scope[1].id} takes a non-negative integer, on #{where.id}" %}
            {% end %}
            # The limits are UInt32.
            {% if value > 4294967295 %}
              {% raise "logbuch: #{name}:#{scope[1].id} takes at most 4294967295, on #{where.id}" %}
            {% end %}
            {% if omit %}
              {% raise "logbuch: #{name}: has no effect on :omit, on #{where.id}" %}
            {% end %}
            {% if scope[1] == "" && !redacted.empty? %}
              {% raise "logbuch: #{name}: has no effect on :redacted, which logs \"***\", on #{where.id}" %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end

  # :nodoc:
  #
  # Checks that the `cap:` and `length:` in *options*, the named arguments of
  # a `@[LogAs]` without a converter, and its `items(...)`, *rule*, can change
  # how a value of *type* is logged at *detail*; *where* names the parameter
  # or field, and *scope* how the messages name the options, such as
  # `" in items(...)"`.
  # *type* is the full name of the declared type, starting with `::`, or nil
  # when it is not known, as for a parameter without a type or with a union;
  # nil, a module, a name that does not resolve here, and a type that it or a
  # subclass converts with a `to_trace` of its own pass unchecked. *detail* is
  # the name of the `Detail` a parameter is logged at, or nil for a field: a
  # field's detail only sets from which detail of the object around it the
  # field is shown, and its value is converted at that object's detail, so a
  # field marked `:id` is logged at `Summary` and `Full` too. *id_field* says
  # the field is marked `:id`, so at `Id` its value is written into the
  # identity of the object around it. It must be expanded in a method, where
  # the fields of every type are known. Expands to nothing.
  #
  # `cap:` limits only arrays, deques, sets, slices and hashes. `length:`
  # cuts only what is text: a string, an exception's message, the text of a
  # type in `VALUE_TYPES`, the `inspect` text of an object that did not opt
  # in to field logging, and the identity of an object; so it fails on the
  # stdlib types logbuch converts without text, characters included, on
  # collections, whose values get the settings again, and on an object logged
  # by its fields where it is not logged as its identity: a parameter not
  # logged at `Id`, or a field not marked `:id`. Strings, value types,
  # exceptions and collections keep their limits at `Id`.
  #
  # `items(...)` goes only on a collection, a tuple or a named tuple too. Its
  # options, unless it has a converter, are checked the same way against the
  # type of the items, each element type of a tuple or named tuple, at its
  # detail; a union is not checked.
  macro __check_limit_target(type, options, where, detail = nil, id_field = false, rule = nil, scope = "")
    {% resolved = type ? parse_type(type).resolve? : nil %}
    {% if resolved.is_a?(TypeNode) && !resolved.union? && !resolved.module? %}
      # The types whose `to_trace` logbuch defines, which a type's own
      # `to_trace` would replace. `Exception` is missing on purpose: its
      # `to_trace` cuts the message. The collections and value types the
      # program may lack are listed whether or not their `to_trace` is
      # defined yet when this expands.
      {% builtin = %w[Object Reference Struct String Symbol Char Nil Bool Time Enum Int8 Int16 Int32 Int64 Int128 UInt8 UInt16 UInt32 UInt64 UInt128 Float32 Float64 Array Slice Hash Tuple NamedTuple] + ::Logbuch::COLLECTION_TYPES + ::Logbuch::VALUE_TYPES %}
      {% own = ([resolved] + resolved.ancestors).reject { |base| builtin.includes?(base.name(generic_args: false).stringify) } + resolved.all_subclasses %}
      {% unless own.any? { |base| base.methods.any? { |method| method.name == "to_trace" } } %}
        {% shown = type.gsub(/^::/, "") %}
        # A collection the program lacks is no base to compare with.
        {% collection = (%w[Array Slice Hash] + ::Logbuch::COLLECTION_TYPES).any? { |name| (base = parse_type("::#{name.id}").resolve?) && resolved <= base } %}
        {% container = collection || resolved <= ::Tuple || resolved <= ::NamedTuple %}
        # `length:` on a hash cuts its keys.
        {% keyed = resolved <= ::Hash %}
        {% text = resolved == ::String || ([resolved] + resolved.ancestors).any? { |base| ::Logbuch::VALUE_TYPES.includes?(base.name(generic_args: false).stringify) } %}
        {% object = !container && !text && !(resolved <= ::Enum) && !builtin.includes?(resolved.name(generic_args: false).stringify) %}
        {% if options && options[:cap] && !collection %}
          {% raise "logbuch: cap:#{scope.id} has no effect on #{shown.id}, which is not an array, deque, set, slice or hash: it limits the items of a collection only, on #{where.id}" %}
        {% end %}
        {% if options && options[:length] && container && !keyed %}
          {% raise "logbuch: length:#{scope.id} has no effect on #{shown.id}: it cuts a string or inspect text only, not the values inside a collection#{scope == "" ? "; use items(length: ...)".id : "".id}, on #{where.id}" %}
        {% end %}
        {% if options && options[:length] && !text && !object && !keyed %}
          {% raise "logbuch: length:#{scope.id} has no effect on #{shown.id}: it cuts a string or inspect text only, on #{where.id}" %}
        {% end %}
        # The same test as in `__object_to_trace`, which decides whether the
        # object is logged by its fields or with `inspect`.
        {% if options && options[:length] && object %}
          {% chain = [resolved] + resolved.ancestors %}
          # Resolved, not named, so this file builds without `tracing.cr`.
          {% tracing = parse_type("::Logbuch::Tracing").resolve? %}
          {% fields = chain.any?(&.annotation(::Logbuch::Annotations::LogType)) || (tracing && resolved <= tracing) %}
          {% fields = fields || chain.any? { |base| base.methods.any? { |method| method.name == "initialize" && method.args.any?(&.annotation(::Logbuch::Annotations::LogAs)) } } %}
          {% fields = fields || resolved.instance_vars.any?(&.annotation(::Logbuch::Annotations::LogAs)) %}
          {% if fields && detail != "Id" && !id_field %}
            {% raise "logbuch: length:#{scope.id} has no effect on #{shown.id}, which is logged by its fields: it cuts a string or inspect text only; put length: on the fields, on #{where.id}" %}
          {% end %}
        {% end %}
        {% if rule %}
          {% unless container %}
            {% raise "logbuch: items(...) has no effect on #{shown.id}, which is not an array, deque, set, slice, hash, tuple or named tuple: it sets how the items of a collection are logged, on #{where.id}" %}
          {% end %}
          {% item_options = {} of SymbolLiteral => ASTNode %}
          {% for named in rule.named_args || [] of ASTNode %}
            {% item_options[named.name.symbolize] = named.value %}
          {% end %}
          {% if !item_options[:converter] && (item_options[:cap] || item_options[:length]) %}
            # The items convert at the detail of `items(...)`, else at the
            # collection's.
            {% item_detail = rule.args.empty? ? detail : ::Logbuch::DETAIL_NAMES[rule.args[0].stringify.gsub(/^::/, "")] %}
            # The type variables of a collection are its item type, a hash's
            # its key and value types, a tuple's its element types and a
            # named tuple's its value types.
            {% item_types = keyed ? [resolved.type_vars[1]] : resolved.type_vars %}
            {% for item_type in item_types %}
              {% if item_type.is_a?(TypeNode) && !item_type.union? %}
                ::Logbuch.__check_limit_target({{ "::#{item_type}" }}, {{ {cap: item_options[:cap], length: item_options[:length]} }}, {{ where }}, {{ item_detail }}, false, nil, " in items(...)")
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end

  # :nodoc:
  #
  # Expands to the conversion of *value*, a parameter or field, by its
  # `@[LogAs]`, whose positional arguments are *args* and named ones
  # *options*, each nil when there are none: a field's with *tracer*, the
  # tracer converting the object around it, a parameter's with *detail*, the
  # `Detail` member it is logged at. `converter:`, or `:redacted` without
  # one, converts the value first; `cap:` and `length:` limit it. An
  # `items(...)` converts each item of it with its own detail, limits and
  # converter, through `Tracer#__convert_items`; with a converter of the
  # value too, its result is what the items come from, and if it raises,
  # the value shows a placeholder naming the exception class. It trusts the
  # annotation, which `__check_log_as` has checked.
  macro __convert_as(value, args, options, tracer = nil, detail = nil)
    {% args = args || [] of ASTNode %}
    {% converter = options ? options[:converter] : nil %}
    {% redacted = args.any? { |arg| arg.is_a?(SymbolLiteral) && arg.id.stringify == "redacted" } %}
    {% rule = args.find { |arg| arg.is_a?(Call) && arg.name.stringify == "items" } %}
    {% block = converter ? "{ |#{converter.args[0].name}| #{converter.body} }" : (redacted ? "{ |_value| \"***\" }" : "") %}
    {% limits = "cap: #{(options && options[:cap]) || "nil".id}, length: #{(options && options[:length]) || "nil".id}" %}
    {% receiver = tracer ? tracer.stringify : "::Logbuch" %}
    {% target = detail ? ", #{detail}" : "" %}
    {% if rule && !redacted %}
      {% item_options = {} of SymbolLiteral => ASTNode %}
      {% for named in rule.named_args || [] of ASTNode %}
        {% item_options[named.name.symbolize] = named.value %}
      {% end %}
      {% item_detail = rule.args.empty? ? "nil" : "::Logbuch::Detail::#{::Logbuch::DETAIL_NAMES[rule.args[0].stringify.gsub(/^::/, "")].id}" %}
      {% item_converter = item_options[:converter] %}
      {% item_block = item_converter ? "{ |#{item_converter.args[0].name}| #{item_converter.body} }" : "{ |item| item }" %}
      {% item_limits = "item_detail: #{item_detail.id}, item_cap: #{item_options[:cap] || "nil".id}, item_length: #{item_options[:length] || "nil".id}" %}
      {% if block == "" %}
        {{ receiver.id }}.__convert_items({{ value }}{{ target.id }}, {{ limits.id }}, {{ item_limits.id }}) {{ item_block.id }}
      {% else %}
        begin
          %converted = ::Logbuch.__inspected({{ value }}) {{ block.id }}
        rescue %error
          ::Log::Metadata::Value.new("#<convert raised " + %error.class.name + ">")
        else
          {{ receiver.id }}.__convert_items(%converted{{ target.id }}, {{ limits.id }}, {{ item_limits.id }}) {{ item_block.id }}
        end
      {% end %}
    {% else %}
      {{ receiver.id }}.{{ (tracer ? "convert" : "__convert").id }}({{ value }}{{ target.id }}, {{ limits.id }}) {{ block.id }}
    {% end %}
  end

  # :nodoc:
  #
  # Checks the `@[LogAs]` of every field of every class and struct in the
  # program, whether or not the type is converted, and in every build. Typing
  # it is the check, so it is only ever typed, by the `typeof` below, before
  # the code that follows `require "logbuch"`. It is a method because the
  # instance variables of a type are known only inside one, not in a
  # `macro finished`. A field is checked in the type that declares it, and in
  # a generic type for all its instances. The `@[LogAs]` on an `initialize`
  # parameter is checked as a parameter by the top-level `macro finished` in
  # `tracing.cr`, and here against the type of the field it sets.
  def self.__check_fields : Nil
    {% begin %}
      {% seen = {} of String => Bool %}
      {% for type in Object.all_subclasses %}
        {% if (type.class? || type.struct?) && type.instance == type && type.type_vars.all?(&.is_a?(MacroId)) && !seen[type.stringify] %}
          {% seen[type.stringify] = true %}
          {% type_name = type.name(generic_args: false) %}
          {% ivars = type.instance_vars %}
          {% inherited = type.superclass ? type.superclass.instance_vars.map(&.name.stringify) : [] of String %}
          # In a generic type, or one that inherits from a generic instance,
          # a field may be declared with a type variable, so its type here is
          # only one of those it can have.
          {% typed = ([type] + type.ancestors).all? { |base| !(base.class? || base.struct?) || base.type_vars.empty? } %}
          {% markers = [] of ASTNode %}
          {% for ivar in ivars %}
            {% found = ivar.annotations(::Logbuch::Annotations::LogAs) %}
            {% unless found.empty? || inherited.includes?(ivar.name.stringify) %}
              {% where = "field #{type_name}@#{ivar.name}" %}
              {% if found.size > 1 %}
                {% raise "logbuch: #{where.id} has more than one @[LogAs]" %}
              {% end %}
              ::Logbuch.__check_log_as({{ found[0].args.empty? ? nil : found[0].args }}, {{ found[0].named_args.empty? ? nil : found[0].named_args }}, {{ where }})
              {% markers << {ivar, found[0], where} %}
            {% end %}
          {% end %}
          {% for init in type.methods.select { |method| method.name == "initialize" } %}
            {% for arg in init.args %}
              {% ivar = ivars.find { |var| var.name.stringify == arg.name.stringify } %}
              {% found = arg.annotations(::Logbuch::Annotations::LogAs) %}
              {% if ivar && found.size == 1 %}
                {% markers << {ivar, found[0], "parameter #{arg.internal_name} of #{type_name}#initialize"} %}
              {% end %}
            {% end %}
          {% end %}
          # A converter's result is what the limits apply to.
          {% for marker in markers %}
            {% rule = marker[1].args.find { |arg| arg.is_a?(Call) && arg.name.stringify == "items" } %}
            {% if typed && (marker[1][:cap] || marker[1][:length] || rule) && !marker[1][:converter] && !marker[0].type.union? %}
              ::Logbuch.__check_limit_target({{ "::#{marker[0].type}" }}, {{ marker[1].named_args.empty? ? nil : marker[1].named_args }}, {{ marker[2] }}, nil, {{ marker[1].args.any? { |arg| ::Logbuch::DETAIL_NAMES[arg.stringify.gsub(/^::/, "")] == "Id" } }}, {{ rule }})
            {% end %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end

  # :nodoc:
  #
  # Expands, inside a `to_trace(tracer)` method, to the conversion of the
  # receiver: by its fields when the type opted in (`@[LogType]`, an include
  # of `Logbuch::Tracing`, or a `@[LogAs]` on a field or on an `initialize`
  # parameter of the type or an ancestor), else with `inspect`, cut to the
  # length limit for the value. At `Detail::Id`, the object is logged as its
  # identity instead, by `Tracer#__identity`, whether it opted in or not.
  #
  # Inside a `__logbuch_identity(tracer, io, held)` method, it expands to the
  # writing of the identity of a type without fields marked `:id` to *io*:
  # the `inspect` text of a type that did not opt in and has no `to_trace` of
  # its own, else its full name without type arguments and, for a class, its
  # object id in hex, as `Reference#to_s` writes it: `#<Order:0x10a3f2c40>`.
  # A struct has no object id and writes only its type, as in `#<Point>`:
  # anything taken from its fields, such as a hash, could give away a
  # redacted value, even one inside a nested struct.
  #
  # Inside an `inspect(io)` method, it expands to the `inspect` of a type
  # that opted in, unless its `@[LogType]` says `inspect: :off`: Crystal's
  # form with only the fields shown at the `inspect:` detail, `Summary` by
  # default, by the rules below, so `:redacted` ones as `"***"` and
  # converted ones as their converter's result, read under the type's
  # `lock:`: `#<Account:0x10a3f2c40 @id="a1", @password="***">` for a class,
  # `Account(@id="a1", @password="***")` for a struct. Any other type keeps
  # Crystal's `inspect`. Inside `pretty_print(pp)`, it expands to that text
  # for such a type, and to Crystal's `pretty_print` for any other.
  #
  # Inside a `__logbuch_key(tracer, held)` method, it expands to the
  # receiver's identity when it has fields marked `:id`, on the field or on
  # the `initialize` parameter that sets it: the one field's value, or a hash
  # of them by name, read under the type's `lock:` unless *held* says this
  # fiber holds it. The tracer converts them at `Detail::Id`, so an object in
  # one logs its own identity. Without such a field, it expands to nil.
  #
  # The fields follow their detail rules:
  #
  # - a field with a detail in its `@[LogAs]` is included when the tracer's
  #   detail is at least that detail, and an `:omit` field never; a
  #   `converter:` block such as `->(value) { value.upcase }` converts the
  #   value first;
  # - a field without one needs `Summary` if every type it can hold is a
  #   value type (a struct, number, `Bool`, `Nil`, `Symbol` or enum, but
  #   not a `Set`) or a `String`, and `Full` otherwise;
  # - a `:redacted` field is logged as `"***"`, or as its converter's
  #   result.
  #
  # It trusts the annotations: `__check_fields` and the top-level
  # `macro finished` in `tracing.cr` have checked them.
  macro __object_to_trace
    {% verbatim do %}
      {% begin %}
        # An instance variable set by an `initialize` parameter such as
        # `@[LogAs(:omit)] @token` carries no annotation itself; the
        # parameter does. The annotations of those parameters are collected
        # once, the type's own first, then its ancestors'.
        {% init_markers = {} of String => ASTNode %}
        {% for type in [@type] + @type.ancestors %}
          {% for init in type.methods.select { |method| method.name == "initialize" } %}
            {% for arg in init.args %}
              {% found = arg.annotations(::Logbuch::Annotations::LogAs) %}
              {% if !found.empty? && !init_markers[arg.name.stringify] %}
                {% init_markers[arg.name.stringify] = found %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
        # `@[LogType]` on the type or an ancestor opts it in, and with
        # `lock: @lock` converts the fields while holding the lock.
        {% type_annotations = ([@type] + @type.ancestors).map(&.annotation(::Logbuch::Annotations::LogType)).select { |anno| anno } %}
        {% lock = type_annotations.map { |anno| anno[:lock] }.select { |arg| arg }.first %}
        # Each field as `{ivar, minimum detail, converting block, limits, marked
        # :id, its @[LogAs] or nil}`. A `@[Logged]` on a field is not an error: Crystal copies the
        # annotations of a method onto an instance variable it assigns, so `@x`
        # of a traced `def set(v); @x = v; end` carries one too, and the traced
        # method shows only its wrapper here, so the two look alike.
        {% fields = [] of ASTNode %}
        {% marked = !init_markers.empty? %}
        {% for ivar in @type.instance_vars %}
          {% found = ivar.annotations(::Logbuch::Annotations::LogAs) %}
          {% if found.empty? %}
            {% found = init_markers[ivar.name.stringify] || found %}
          {% end %}
          {% if !found.empty? %}
            {% marked = true %}
          {% end %}
          {% anno = found[0] %}
          {% block = "" %}
          {% limits = {cap: nil, length: nil} %}
          {% field_detail = nil %}
          {% if anno %}
            {% field_detail = anno.args.map { |arg| ::Logbuch::DETAIL_NAMES[arg.stringify.gsub(/^::/, "")] }.find { |name| name } %}
            {% redacted = anno.args.any? { |arg| arg.is_a?(SymbolLiteral) && arg.id.stringify == "redacted" } %}
            {% converter = anno[:converter] %}
            {% if converter.is_a?(ProcLiteral) && converter.args.size == 1 %}
              {% block = " { |#{converter.args[0].name}| #{converter.body} }" %}
            {% elsif redacted %}
              {% block = " { |_value| \"***\" }" %}
            {% end %}
            {% limits = {cap: anno[:cap], length: anno[:length]} %}
          {% end %}
          # Without a detail, `:redacted` keeps the detail the field has
          # without an annotation.
          {% if field_detail %}
            {% minimum = field_detail %}
          {% else %}
            {% types = ivar.type.union? ? ivar.type.union_types : [ivar.type] %}
            # A program without `Set` has no set field.
            {% set = parse_type("::Set").resolve? %}
            {% minimum = types.all? { |type| (type <= Value && !(set && type <= set)) || type == String } ? "Summary" : "Full" %}
          {% end %}
          {% fields << {ivar, minimum, block, limits, minimum == "Id", anno} %}
        {% end %}
        # Resolved, not named, so this file builds without `tracing.cr`.
        {% tracing = parse_type("::Logbuch::Tracing").resolve? %}
        {% opted_in = !type_annotations.empty? || (tracing && @type <= tracing) || marked %}
        # The detail `inspect` shows, from the `inspect:` of the nearest
        # `@[LogType]` that sets it, `Summary` by default; nil for `:off`.
        {% inspect_mode = type_annotations.map { |anno| anno[:inspect] }.find { |arg| !arg.nil? } %}
        {% inspect_detail = inspect_mode ? {"off" => nil, "id" => "Id", "summary" => "Summary", "full" => "Full"}[inspect_mode.id.stringify] : "Summary" %}
        {% masked = opted_in && inspect_detail %}
        {% id_fields = opted_in ? fields.select { |field| field[4] } : [] of ASTNode %}
        {% if @def.name.stringify == "__logbuch_identity" %}
          # A type that did not opt in and has no `to_trace` of its own is
          # logged with `inspect` at every other detail, so its identity
          # shows nothing more with it. A collection, such as an `Array`,
          # converts its items instead, which `inspect` would bypass.
          {% owner = ([@type] + @type.ancestors).find { |base| base.methods.any? { |method| method.name == "to_trace" } } %}
          {% if !opted_in && %w[Reference Struct].includes?(owner.name(generic_args: false).stringify) %}
            inspect(io)
          {% else %}
            io << "#<" << {{ @type.name(generic_args: false).stringify }}
            {% if !@type.struct? %}
              io << ":0x"
              object_id.to_s(io, 16)
            {% end %}
            io << '>'
          {% end %}
        {% elsif @def.name.stringify == "inspect" %}
          {% if masked %}
            {% ranks = {"Id" => 1, "Summary" => 2, "Full" => 3} %}
            {% shown = fields.select { |field| field[1] != "Omit" && ranks[field[1]] <= ranks[inspect_detail] } %}
            {% if @type.struct? %}
              io << {{ @type.name.id.stringify }} << '('
              ::Logbuch.__locked({{ lock || nil }}) do
                {% for field, index in shown %}
                  {% if index > 0 %}io << ", "{% end %}
                  io << {{ "@#{field[0].name}=" }}
                  {% if field[2] == "" %}@{{ field[0].name }}.inspect(io){% else %}::Logbuch.__inspected(@{{ field[0].name }}){{ field[2].id }}.inspect(io){% end %}
                {% end %}
              end
              io << ')'
            {% else %}
              io << "#<" << {{ @type.name.id.stringify }} << ":0x"
              object_id.to_s(io, 16)
              executed = exec_recursive(:inspect) do
                ::Logbuch.__locked({{ lock || nil }}) do
                  {% for field, index in shown %}
                    {% if index > 0 %}io << ','{% end %}
                    io << {{ " @#{field[0].name}=" }}
                    {% if field[2] == "" %}@{{ field[0].name }}.inspect(io){% else %}::Logbuch.__inspected(@{{ field[0].name }}){{ field[2].id }}.inspect(io){% end %}
                  {% end %}
                end
              end
              io << " ..." unless executed
              io << '>'
            {% end %}
          {% else %}
            previous_def
          {% end %}
        {% elsif @def.name.stringify == "pretty_print" %}
          {% if masked %}
            pp.text inspect
          {% else %}
            previous_def
          {% end %}
        {% elsif @def.name.stringify == "__logbuch_key" %}
          {% if id_fields.size == 1 %}
            {% field = id_fields[0] %}
            ::Logbuch.__locked(held ? nil : {{ lock || nil }}) do
              tracer.convert(@{{ field[0].name }}, cap: {{ field[3][:cap] }}, length: tracer.__id_length({{ field[3][:length] }})){{ field[2].id }}
            end
          {% elsif id_fields.size > 1 %}
            ::Logbuch.__locked(held ? nil : {{ lock || nil }}) do
              hash = {} of String => ::Log::Metadata::Value
              {% for field in id_fields %}
                hash[{{ field[0].name.stringify }}] = tracer.convert(@{{ field[0].name }}, cap: {{ field[3][:cap] }}, length: tracer.__id_length({{ field[3][:length] }})){{ field[2].id }}
              {% end %}
              ::Log::Metadata::Value.new(hash)
            end
          {% else %}
            nil
          {% end %}
        {% else %}
          return tracer.__identity(self) if tracer.detail <= ::Logbuch::Detail::Id
          {% if lock %}::Logbuch.__locked({{ lock }}) do{% end %}
          {% if opted_in %}
            hash = {} of String => ::Log::Metadata::Value
            {% for field in fields %}
              {% if field[1] != "Omit" %}
                if tracer.detail >= ::Logbuch::Detail::{{ field[1].id }}
                  hash[{{ field[0].name.stringify }}] = ::Logbuch.__convert_as(@{{ field[0].name }}, {{ field[5] && !field[5].args.empty? ? field[5].args : nil }}, {{ field[5] && !field[5].named_args.empty? ? field[5].named_args : nil }}, tracer: tracer)
                end
              {% end %}
            {% end %}
            ::Log::Metadata::Value.new(hash)
          {% else %}
            ::Log::Metadata::Value.new(::Logbuch.__inspect(self, tracer.length))
          {% end %}
          {% if lock %}end{% end %}
        {% end %}
      {% end %}
    {% end %}
  end
end

# Checks the fields when the program is typed; see `Logbuch.__check_fields`.
typeof(::Logbuch.__check_fields)
