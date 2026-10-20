require "array"
require "char"
require "enum"
require "exception"
require "hash"
require "int"
require "io"
require "log"
require "named_tuple"
require "object"
require "slice"
require "string"
require "symbol"
require "time"
require "tuple"

require "./field_rules"
require "./limits"
require "./tracer"

# Conversion of values into structured trace data. Types override
# `to_trace(tracer)` to control how they appear in a trace; strings and
# collections are capped by the limits the tracer carries.

class Object
  # Converts this value into trace data with *tracer*. Values without a
  # conversion of their own are logged with `inspect`, cut to the length
  # limit.
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new(Logbuch.__inspect(self, tracer.length))
  end
end

{% for type in [Nil, Bool, Time, Int32, Int64, UInt32, UInt64, Float32, Float64] %}
  # :nodoc:
  struct {{ type }}
    # :nodoc:
    def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
      Log::Metadata::Value.new(self)
    end
  end
{% end %}

# :nodoc:
class String
  # :nodoc:
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new(Logbuch.__truncate(self, tracer.length))
  end
end

# :nodoc:
struct Char
  # :nodoc:
  #
  # Logged with `inspect`, as `'a'`, at every detail: a character is its own
  # identity, so `Detail::Id` keeps it too.
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new(inspect)
  end
end

{% for pair in [{Int8, Int32}, {Int16, Int32}, {UInt8, UInt32}, {UInt16, UInt32}] %}
  # :nodoc:
  struct {{ pair[0] }}
    # :nodoc:
    def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
      Log::Metadata::Value.new({{ pair[1] }}.new(self))
    end
  end
{% end %}

{% for type in [Int128, UInt128, Symbol, Enum] %}
  # :nodoc:
  struct {{ type }}
    # :nodoc:
    def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
      Log::Metadata::Value.new(to_s)
    end
  end
{% end %}

# :nodoc:
class Array(T)
  # :nodoc:
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    __logbuch_items(tracer) { |item| tracer.convert(item) }
  end

  # :nodoc:
  #
  # Converts this collection with what the block returns for each item.
  # See `Tracer#__convert_items`.
  def __logbuch_items(tracer : Logbuch::Tracer, & : T -> Log::Metadata::Value) : Log::Metadata::Value
    Logbuch.__items(self, size, tracer) { |item| yield item }
  end
end

# :nodoc:
struct Slice(T)
  # :nodoc:
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    __logbuch_items(tracer) { |item| tracer.convert(item) }
  end

  # :nodoc:
  #
  # Converts this collection with what the block returns for each item.
  # See `Tracer#__convert_items`.
  def __logbuch_items(tracer : Logbuch::Tracer, & : T -> Log::Metadata::Value) : Log::Metadata::Value
    Logbuch.__items(self, size, tracer) { |item| yield item }
  end
end

# :nodoc:
struct Tuple
  # :nodoc:
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    __logbuch_items(tracer) { |item| tracer.convert(item) }
  end

  # :nodoc:
  #
  # Converts this collection with what the block returns for each element.
  # See `Tracer#__convert_items`.
  def __logbuch_items(tracer : Logbuch::Tracer, &) : Log::Metadata::Value
    items = Array(Log::Metadata::Value).new(size)
    each { |value| items << yield value }
    Log::Metadata::Value.new(items)
  end

  # :nodoc:
  #
  # A tuple takes a level of nesting, like an array. See `Tracer#convert`.
  def __logbuch_level? : Bool
    true
  end

  # :nodoc:
  #
  # Writes the identity of this tuple to *io*, which the depth limit logs:
  # `#<Tuple>`, like a struct without `:id` fields. See `Tracer#__identity`.
  def __logbuch_identity(_tracer : Logbuch::Tracer, io : IO, _held : Bool) : Nil
    io << "#<Tuple>"
  end
end

# :nodoc:
class Hash(K, V)
  # :nodoc:
  #
  # Logs this hash as an array of key and value pairs, `[["a1", 1]]`, so
  # every key keeps the form it converts to, whatever its type, and no two
  # entries can clash.
  #
  # Each key is converted at `Detail::Id`, whatever the detail of this hash
  # (see `Tracer#__key`): a string is cut as a string value is, a symbol is
  # logged as its text, an object as its identity, such as `a1` for one
  # `:id` field, `{"row" => 12, "letter" => "A"}` for several, or
  # `#<Session:0x…>` and `#<Badge>` for none, and a collection its items at
  # `Detail::Id`. The depth limit and cycles hold for a key too. The length
  # limit of this hash cuts each string of a key.
  #
  # Entries past the item limit are counted in a last item, `… 900 more`,
  # as in an array.
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    __logbuch_items(tracer) { |value| tracer.convert(value) }
  end

  # :nodoc:
  #
  # Converts this hash with what the block returns for each value; the keys
  # convert as `#to_trace` says. See `Tracer#__convert_items`.
  def __logbuch_items(tracer : Logbuch::Tracer, & : V -> Log::Metadata::Value) : Log::Metadata::Value
    limit = tracer.cap
    length = tracer.length
    pairs = Array(Log::Metadata::Value).new((size < limit ? size : limit.to_i32) + 1)
    each do |key, value|
      break if pairs.size == limit
      pairs << Log::Metadata::Value.new([tracer.__key(key, length: length), yield value])
    end
    pairs << Log::Metadata::Value.new("… #{size - limit} more") if size > limit
    Log::Metadata::Value.new(pairs)
  end
end

# :nodoc:
struct NamedTuple
  # :nodoc:
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    __logbuch_items(tracer) { |value| tracer.convert(value) }
  end

  # :nodoc:
  #
  # Converts this collection with what the block returns for each value.
  # See `Tracer#__convert_items`.
  def __logbuch_items(tracer : Logbuch::Tracer, &) : Log::Metadata::Value
    hash = {} of String => Log::Metadata::Value
    each { |key, value| hash[key.to_s] = yield value }
    Log::Metadata::Value.new(hash)
  end

  # :nodoc:
  #
  # A named tuple takes a level of nesting, like a hash. See
  # `Tracer#convert`.
  def __logbuch_level? : Bool
    true
  end

  # :nodoc:
  #
  # Writes the identity of this named tuple to *io*, which the depth limit
  # logs: `#<NamedTuple>`, like a struct without `:id` fields. See
  # `Tracer#__identity`.
  def __logbuch_identity(_tracer : Logbuch::Tracer, io : IO, _held : Bool) : Nil
    io << "#<NamedTuple>"
  end
end

# :nodoc:
class Exception
  # :nodoc:
  #
  # Logs the type, the message and the cause. A `message` or a class name
  # that raises shows as a placeholder, so the line keeps the rest.
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    hash = {"type" => Log::Metadata::Value.new(Logbuch.__type_name(self))}
    Logbuch.__message(self).try { |text| hash["message"] = Log::Metadata::Value.new(Logbuch.__truncate(text, tracer.length)) }
    cause.try { |inner| hash["cause"] = tracer.convert(inner) }
    Log::Metadata::Value.new(hash)
  end
end

module Logbuch
  # :nodoc:
  #
  # The collections of the standard library that logbuch does not use itself,
  # by full name. Not every program has them, so the `macro finished` below
  # gives each a `to_trace` that logs its items like an array's only when the
  # program does. Read by macros only.
  COLLECTION_TYPES = %w[Deque Set]

  # :nodoc:
  #
  # The value types of the standard library whose value is their identity,
  # by full name. Not every program has them, so the `macro finished` below
  # gives each a `to_trace` only when the program does. Read by macros only.
  VALUE_TYPES = %w[Complex MIME::MediaType Path SemanticVersion Socket::IPAddress Socket::UNIXAddress Time::Location Time::Span URI UUID]
end

# Gives each type of the standard library that a program may lack a
# `to_trace`, if the program has it. The hook runs once the whole program is
# read, so it finds a type whatever the order of the requires, and it neither
# requires a library nor names a type the program lacks.
#
# A type in `Logbuch::COLLECTION_TYPES` logs its items like an array, within
# the item limit. A type in `Logbuch::VALUE_TYPES` logs its `to_s` at every
# detail, cut to the length limit like `inspect` text, so `Detail::Id` keeps
# the value: `Path["/tmp"]` logs as `/tmp`, `1.second` as `00:00:01`. A URI
# logs its password as `***`, as `:redacted` does.
#
# A name that resolves to an alias or to a module of the program is left
# alone, and so is a type with a `to_trace` of its own, which a definition
# here would replace. A generic type is reopened with its own type
# parameters, such as `Set(T)`.
macro finished
  {% for name in ::Logbuch::COLLECTION_TYPES + ::Logbuch::VALUE_TYPES %}
    {% type = parse_type("::#{name.id}").resolve? %}
    {% if type.is_a?(TypeNode) && (type.class? || type.struct?) && type.name(generic_args: false).stringify == name && !type.methods.any? { |method| method.name == "to_trace" } %}
      # :nodoc:
      {{ (type.struct? ? "struct" : "class").id }} ::{{ name.id }}{% unless type.type_vars.empty? %}({{ type.type_vars.splat }}){% end %}
        # :nodoc:
        def to_trace(tracer : ::Logbuch::Tracer) : ::Log::Metadata::Value
          {% if ::Logbuch::COLLECTION_TYPES.includes?(name) %}
            __logbuch_items(tracer) { |item| tracer.convert(item) }
          {% else %}
            {% if name == "URI" %}
              # The text has the password only after a user name, both
              # percent-encoded, so the first `:%2A%2A%2A@` is the password.
              if user && password
                uri = dup
                uri.password = "***"
                return ::Log::Metadata::Value.new(::Logbuch.__text(uri.to_s.sub(":%2A%2A%2A@", ":***@"), tracer.length))
              end
            {% end %}
            ::Log::Metadata::Value.new(::Logbuch.__text(self, tracer.length))
          {% end %}
        end

        {% if ::Logbuch::COLLECTION_TYPES.includes?(name) %}
          # :nodoc:
          #
          # Converts this collection with what the block returns for each
          # item. See `Tracer#__convert_items`.
          def __logbuch_items(tracer : ::Logbuch::Tracer, &) : ::Log::Metadata::Value
            ::Logbuch.__items(self, size, tracer) { |item| yield item }
          end
        {% end %}
      end
    {% end %}
  {% end %}
end
