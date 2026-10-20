require "fiber"
require "primitives"
require "reference"
require "struct"
require "tuple"

require "./tracer"

# :nodoc:
class Fiber
  # :nodoc:
  #
  # The tracer this fiber converts traced values with, kept so that a
  # conversion allocates nothing.
  property __logbuch_tracer : Logbuch::Tracer? = nil

  # Only the traced methods read the call, and `-Dlogbuch=off` generates none.
  {% unless %w[off 0].includes?(flag?(:logbuch)) %}
    # :nodoc:
    #
    # The traced call this fiber is logging: the receiver's identity, the
    # method name and the label of the wrapper. A traced method that the call
    # reaches through `super` sees it and does not log again.
    property __logbuch_call : Tuple({UInt64, Int32}, String, String)? = nil
  {% end %}
end

{% unless %w[off 0].includes?(flag?(:logbuch)) %}
  # :nodoc:
  class Object
    # :nodoc:
    #
    # Identifies this value as the receiver of a traced call, so that a call
    # through `super` can be told from a call on another object: where it is
    # stored and its type id. A value with nothing stored, such as a type,
    # has its type id only. See `Logbuch.__super_call?`.
    def __logbuch_receiver : {UInt64, Int32}
      {0_u64, crystal_type_id}
    end
  end

  # :nodoc:
  class Reference
    # :nodoc:
    def __logbuch_receiver : {UInt64, Int32}
      {object_id, crystal_type_id}
    end
  end

  # :nodoc:
  struct Struct
    # :nodoc:
    #
    # A struct method takes `self` by reference, so its first instance
    # variable, at offset 0, is where the struct is stored: the same in an
    # override and in the method it reaches through `super`, and different
    # for another struct, or a copy. Crystal does not let `pointerof` take
    # `self`. A struct stored at the start of another shares its address, so
    # the type id tells the two apart. A struct without instance variables has
    # no address to read and is identified by its type id only, so all of a
    # type's instances are one receiver.
    def __logbuch_receiver : {UInt64, Int32}
      \{% begin %}
        \{% field = @type.instance_vars.first %}
        \{% if field %}
          {pointerof(@\{{ field.name }}).address, crystal_type_id}
        \{% else %}
          {0_u64, crystal_type_id}
        \{% end %}
      \{% end %}
    end
  end

  module Logbuch
    # :nodoc:
    #
    # Whether a traced call on *receiver*, its `__logbuch_receiver`, is one
    # that a traced override makes through `super`: the same receiver and
    # method *name*, but another type's wrapper than *label*. A recursive call
    # comes back to the same wrapper and is logged.
    def self.__super_call?(outer : Tuple({UInt64, Int32}, String, String)?, receiver : {UInt64, Int32}, name : String, label : String) : Bool
      return false unless outer
      outer[0] == receiver && outer[1] == name && outer[2] != label
    end
  end
{% end %}
