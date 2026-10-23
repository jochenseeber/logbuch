require "io"
require "log"
require "reference"
require "struct"

require "./field_rules"
require "./locks"
require "./tracer"
require "./values"

# Conversion of objects into trace data. A type that opted in is converted
# from its instance variables by its field rules; any other type is logged with
# `inspect`. At `Detail::Id`, in a cycle and past the depth limit, an object is
# logged as its identity. See `Logbuch.__object_to_trace`.
#
# Each def that expands `__object_to_trace` names `@type` in macro code of its
# own, `{% @type %}`: only that makes Crystal build it once per concrete type.
# Without it, a call through a variable of a parent type, the virtual
# `Parent+`, expands the macro once for `Parent`, and an object of a subclass
# is shown with its parent's fields.

# :nodoc:
class Object
  # :nodoc:
  #
  # The identity of this value from its `:id` fields, which a hash key logs
  # too, or nil for a value without them; *held* says this fiber holds
  # the type's `lock:` already. See `Tracer#__identity`.
  def __logbuch_key(tracer : Logbuch::Tracer, held : Bool = false) : Log::Metadata::Value?
    nil
  end
end

# :nodoc:
class Reference
  # Writes this object as Crystal does, but for a type that opted in to
  # logbuch only with the fields its `inspect:` detail shows, `Summary` by
  # default, `:redacted` ones as `"***"`. See `Logbuch.__object_to_trace`.
  def inspect(io : IO) : Nil
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  def pretty_print(pp) : Nil
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  #
  # Whether this object takes a level of nesting, which the depth limit
  # counts: it does unless the class that defines its `to_trace` is
  # `String` or a stdlib value type in `VALUE_TYPES`, such as `URI`, which
  # hold no other values. Unlike a struct, an object with a `to_trace` of its
  # own takes one too: an object can contain itself, so a list of them would
  # otherwise stop only at `DEPTH_CEILING`. See `Tracer#convert`.
  def __logbuch_level? : Bool
    {% begin %}
      {% owner = ([@type] + @type.ancestors).find { |base| base.methods.any? { |method| method.name == "to_trace" } } %}
      {{ !(%w[String] + ::Logbuch::VALUE_TYPES).includes?(owner.name(generic_args: false).stringify) }}
    {% end %}
  end

  # :nodoc:
  #
  # Writes the identity of this object without `:id` fields, `#<Type:0x…>`
  # or its `inspect` text, to *io*. See `Tracer#__identity`.
  def __logbuch_identity(tracer : Logbuch::Tracer, io : IO, held : Bool) : Nil
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  def __logbuch_key(tracer : Logbuch::Tracer, held : Bool = false) : Log::Metadata::Value?
    {% @type %}
    ::Logbuch.__object_to_trace
  end
end

# :nodoc:
struct Struct
  # Writes this struct as Crystal does, but for a type that opted in to
  # logbuch only with the fields its `inspect:` detail shows, `Summary` by
  # default, `:redacted` ones as `"***"`. See `Logbuch.__object_to_trace`.
  def inspect(io : IO) : Nil
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  def pretty_print(pp) : Nil
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  #
  # Whether this struct takes a level of nesting, which the depth limit
  # counts: it does when logbuch converts it by its fields or with
  # `inspect`, or it is a collection, such as a `Set` or a `Slice`. A struct
  # with a `to_trace` of its own, such as `Time`, a stdlib value type or a
  # value type of the program, takes none. See `Tracer#convert`.
  def __logbuch_level? : Bool
    {% begin %}
      {% owner = ([@type] + @type.ancestors).find { |base| base.methods.any? { |method| method.name == "to_trace" } } %}
      {{ (%w[Struct Slice] + ::Logbuch::COLLECTION_TYPES).includes?(owner.name(generic_args: false).stringify) }}
    {% end %}
  end

  # :nodoc:
  #
  # Writes the identity of this struct without `:id` fields, `#<Type>` or
  # its `inspect` text, to *io*. See `Tracer#__identity`.
  def __logbuch_identity(tracer : Logbuch::Tracer, io : IO, held : Bool) : Nil
    {% @type %}
    ::Logbuch.__object_to_trace
  end

  # :nodoc:
  def __logbuch_key(tracer : Logbuch::Tracer, held : Bool = false) : Log::Metadata::Value?
    {% @type %}
    ::Logbuch.__object_to_trace
  end
end
