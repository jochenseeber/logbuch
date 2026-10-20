require "array"
require "exception"
require "fiber"
require "log"
require "math/math"
require "reference"
require "struct"

require "./detail"
require "./limits"
require "./settings"

module Logbuch
  # Converts one traced value into trace data. It carries the detail, the
  # limits for the value being converted, and the path of objects from the
  # traced value down to that value, which cuts reference cycles and limits
  # nesting. The item and length limits hold for the value being converted
  # only; the depth limit is handed down to the values inside it.
  #
  # A value takes a level of nesting when it can hold other values: an
  # object, a collection, a tuple or named tuple, and a struct logged by its
  # fields or with `inspect`. Strings, numbers, `Bool`, `Nil`, characters,
  # symbols, enums, `Time`, the value types such as `UUID`, `Path` and `URI`,
  # and a struct with a `to_trace` of its own take none, so they are logged
  # by value at the depth limit; the values such a `to_trace` converts take
  # their own levels. An object with a `to_trace` of its own takes a level,
  # since unlike a struct it can contain itself.
  #
  # A type controls how it appears in a trace by defining
  # `to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value`, and converts
  # the values it contains with `#convert`. A `Logbuch.convert` there, or a
  # traced method it calls, continues the conversion with a detail and limits
  # of its own but the same path, so cycles and `DEPTH_CEILING` still cut it
  # off:
  #
  # ```
  # class JobQueue
  #   def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
  #     @lock.synchronize { tracer.convert(@jobs) }
  #   end
  # end
  # ```
  class Tracer
    # How much of each value goes into the trace.
    getter detail : Detail = Detail::Summary

    # The items the array, deque, set, slice or hash being converted may show,
    # its cap; the rest are counted. It holds for that collection only:
    # `#convert` gives each value inside it the settings again.
    getter cap : UInt32 = MAX_CAP

    # The characters the string being converted may show, or the keys of the
    # hash, or the `inspect` text or exception message of the value being
    # converted. It holds for that value only, like `#cap`.
    getter length : UInt32 = MAX_LENGTH

    # The ids of the objects from the traced value down to the one being
    # converted.
    @path = [] of UInt64

    # The number of levels at which nesting stops; see `#levels`.
    @depth = MAX_DEPTH

    # The structs, tuples and named tuples being converted that take a level
    # of nesting; they never enter the path, but count towards the depth
    # limit like the objects on it.
    @levels = 0_u32

    # The structs and objects being converted that take no level of nesting,
    # such as a `Path` or a `URI`. They count towards `DEPTH_CEILING` only,
    # so one that converts itself stops there.
    @leaves = 0_u32

    # The ids of the objects whose identity is being written, so `:id` fields
    # that lead back to one of them stop there.
    @identities = [] of UInt64

    # The length limit of the identity being converted, which its `:id`
    # fields take unless their own is shorter. See `#__id_length`.
    @id_length : UInt32? = nil

    @busy = false

    # :nodoc:
    #
    # The settings this conversion started with, read once at its start so
    # that a `Logbuch.configure` meanwhile does not change it halfway.
    getter __settings : Settings

    # Tracers come from `.use` only: `Logbuch.convert` and the traced methods
    # hand one to a type's `to_trace`.
    private def initialize
      @__settings = Logbuch.settings
    end

    # :nodoc:
    #
    # Runs the block with the fiber's own tracer for one value at *detail*, so
    # that converting allocates nothing. While that tracer is busy, as when a
    # `to_trace` calls `Logbuch.convert` or a converter calls a traced method,
    # the value nests in the conversion under way: it keeps the path, so
    # cycles and `DEPTH_CEILING` reach across, and gets the default limits,
    # with `max_depth` counted from where it starts.
    def self.use(detail : Detail, &)
      fiber = Fiber.current
      tracer = fiber.__logbuch_tracer ||= new
      return tracer.__nest(detail) { yield tracer } if tracer.@busy
      tracer.__start(detail)
      begin
        yield tracer
      ensure
        tracer.__stop
      end
    end

    # :nodoc:
    def __start(@detail : Detail) : Nil
      @busy = true
      settings = @__settings = Logbuch.settings
      @cap = settings.max_cap
      @length = settings.max_length
      @depth = settings.max_depth
      @path.clear
    end

    # :nodoc:
    def __stop : Nil
      @busy = false
      @path.clear
      @levels = 0
      @leaves = 0
      @identities.clear
      @id_length = nil
    end

    # :nodoc:
    #
    # Runs the block with a nested conversion at *detail*, then restores the
    # detail and the limits of the one around it. It keeps the settings that
    # conversion started with.
    def __nest(detail : Detail, &)
      saved_detail, saved_cap, saved_length, saved_depth = @detail, @cap, @length, @depth
      @detail = detail
      @cap = @__settings.max_cap
      @length = @__settings.max_length
      @depth = Math.min(levels + @__settings.max_depth, DEPTH_CEILING)
      begin
        yield
      ensure
        @detail, @cap, @length, @depth = saved_detail, saved_cap, saved_length, saved_depth
      end
    end

    # How many levels of nesting the values around the one being converted
    # take, which the depth limit counts.
    private def levels : UInt32
      @path.size.to_u32 + @levels
    end

    # How many objects and structs the value being converted is nested in,
    # which `DEPTH_CEILING` counts.
    private def nesting : UInt32
      levels + @leaves
    end

    # Converts *value*, a value inside the one being converted. It gets the
    # limits of `Logbuch.settings` unless *cap* or *length* set its own, which
    # hold for *value* itself, not for the values inside it: *cap* limits the
    # items of an array, deque, set, slice or hash, and *length* cuts a
    # string, the keys of a hash, an exception's message, `inspect` text or an
    # identity. The limits are unsigned, so a negative one fails to compile.
    #
    # An object or collection that is already on the path is a cycle, and a
    # value that takes a level of nesting is not shown at the depth limit,
    # nor is any other object or struct nested `DEPTH_CEILING` levels deep:
    # each converts to its identity instead, as `Detail::Id` logs it, such
    # as `"a"`, `#<Order:0x10a3f2c40>` or `#<Point>`.
    def convert(value, *, cap : UInt32? = nil, length : UInt32? = nil) : ::Log::Metadata::Value
      saved_cap, saved_length = @cap, @length
      @cap = cap || @__settings.max_cap
      @length = length || @__settings.max_length
      begin
        # A string holds no other values, so it takes no level of nesting
        # and nothing counts it.
        if value.is_a?(String)
          value.to_trace(self)
        elsif value.is_a?(Reference) || value.is_a?(Struct) || value.is_a?(Tuple) || value.is_a?(NamedTuple)
          value.__logbuch_level? ? convert_level(value) { value.to_trace(self) } : convert_leaf(value) { value.to_trace(self) }
        else
          value.to_trace(self)
        end
      ensure
        @cap, @length = saved_cap, saved_length
      end
    end

    # :nodoc:
    #
    # Converts *value* like `#convert`, with *cap* and *length*, and, when it
    # is an array, deque, set, slice, hash, tuple or named tuple, each of its
    # items, the values of a hash or named tuple, with the item options of an
    # `items(...)`: what the block returns for the item, at *item_detail*
    # unless that is nil, with *item_cap* and *item_length*. If the block
    # raises, the item shows a placeholder naming the exception class. Any
    # other value converts as `#convert` converts it, and so does a
    # collection in a cycle or past the depth limit, as its identity.
    def __convert_items(value, *, cap : UInt32? = nil, length : UInt32? = nil, item_detail : Detail? = nil, item_cap : UInt32? = nil, item_length : UInt32? = nil, &) : ::Log::Metadata::Value
      return convert(value, cap: cap, length: length) unless value.responds_to?(:__logbuch_items)
      saved_cap, saved_length = @cap, @length
      @cap = cap || @__settings.max_cap
      @length = length || @__settings.max_length
      begin
        convert_level(value) do
          value.__logbuch_items(self) do |item|
            converted = begin
              yield item
            rescue error
              next ::Log::Metadata::Value.new("#<convert raised #{error.class}>")
            end
            saved_detail = @detail
            @detail = item_detail if item_detail
            begin
              convert(converted, cap: item_cap, length: item_length)
            ensure
              @detail = saved_detail
            end
          end
        end
      ensure
        @cap, @length = saved_cap, saved_length
      end
    end

    # Whether a value that takes a level of nesting is past the depth limit
    # or `DEPTH_CEILING`, so it converts to its identity.
    private def past_depth? : Bool
      levels >= @depth || nesting >= DEPTH_CEILING
    end

    # Converts *value*, which takes a level of nesting, so it counts towards
    # the depth limit: an object on the path, which also cuts cycles, and a
    # struct, tuple or named tuple, which cannot contain itself, in
    # `@levels`. The block converts it when it is shown.
    private def convert_level(value : Reference | Struct | Tuple | NamedTuple, &) : ::Log::Metadata::Value
      if value.is_a?(Reference)
        id = value.object_id
        # A repeated object is being converted further out, which holds its
        # `lock:` already.
        return __identity(value, held: true) if @path.includes?(id)
        return __identity(value) if past_depth?
        @path << id
        begin
          yield
        ensure
          @path.pop
        end
      else
        return __identity(value) if past_depth?
        @levels += 1
        begin
          yield
        ensure
          @levels -= 1
        end
      end
    end

    # Converts *value*, an object or struct that takes no level of nesting,
    # such as a `URI` or a `Path`. Such an object holds no other values and
    # a struct cannot contain itself, so it never enters the path; it counts
    # towards `DEPTH_CEILING` only, so one whose `to_trace` converts itself
    # stops there. The block converts it when it is shown.
    private def convert_leaf(value : Reference | Struct | Tuple | NamedTuple, &) : ::Log::Metadata::Value
      return __identity(value) if nesting >= DEPTH_CEILING
      @leaves += 1
      begin
        yield
      ensure
        @leaves -= 1
      end
    end

    # :nodoc:
    #
    # The identity of *value*, an object, a struct, a tuple or a named tuple, as
    # `Detail::Id` logs it. With `:id` fields, it is their values, as
    # `__logbuch_key` writes them: the one field's value or a hash of them by
    # name, each converted at `Detail::Id` and each string cut to the length
    # limit for the value. Without, it is the text its
    # `__logbuch_identity` writes, `#<Type:0x…>`, `#<Type>` or its `inspect`
    # text, cut to the length limit like `inspect` text. A cycle and the depth
    # limit convert to it too, so it is the same wherever the object appears; a
    # tuple and a named tuple, which `Detail::Id` logs by their values, take it
    # only at the depth limit. `:id` fields that lead back to an object whose
    # identity is being converted, or nest `DEPTH_CEILING` identities deep, end
    # in `…`. *held* says this fiber holds the type's `lock:` already, as a
    # conversion further out does for an object in a cycle.
    def __identity(value : Reference | Struct | Tuple | NamedTuple, *, held : Bool = false) : ::Log::Metadata::Value
      if value.is_a?(Reference)
        id = value.object_id
        return ::Log::Metadata::Value.new("…") if @identities.includes?(id) || @identities.size >= DEPTH_CEILING
        @identities << id
      end
      saved_detail, saved_id_length = @detail, @id_length
      @detail = Detail::Id
      @id_length = @length
      begin
        value.__logbuch_key(self, held) ||
          ::Log::Metadata::Value.new(Logbuch.__limited(@length) { |io| value.__logbuch_identity(self, io, held) })
      ensure
        @detail, @id_length = saved_detail, saved_id_length
        @identities.pop if value.is_a?(Reference)
      end
    end

    # :nodoc:
    #
    # The length limit an `:id` field converts with: *own*, its `length:`,
    # or inside an identity the identity's limit if that is shorter, so the
    # `length:` of a parameter logged at `Detail::Id` cuts each string of the
    # identity once.
    def __id_length(own : UInt32?) : UInt32?
      limit = @id_length
      return own unless limit
      own ? Math.min(own, limit) : limit
    end

    # :nodoc:
    #
    # Converts *key*, a key of the hash being converted, at `Detail::Id`,
    # whatever the detail of the hash: an object as its identity, a
    # collection its items at `Detail::Id`. *length* is the hash's length
    # limit, which cuts each string of it. Like any value, it takes a level
    # of nesting, so a key already on the path is a cycle and one past the
    # depth limit is cut. See `Hash#to_trace`.
    def __key(key, *, length : UInt32) : ::Log::Metadata::Value
      saved_detail = @detail
      @detail = Detail::Id
      begin
        convert(key, length: length)
      ensure
        @detail = saved_detail
      end
    end

    # Converts what the block returns for *value* instead of *value*, like
    # `#convert`. If the block raises, or converting its result does, the
    # trace shows a placeholder naming the exception class.
    def convert(value, *, cap : UInt32? = nil, length : UInt32? = nil, &) : ::Log::Metadata::Value
      converted = begin
        yield value
      rescue error
        return ::Log::Metadata::Value.new("#<convert raised #{error.class}>")
      end
      begin
        convert(converted, cap: cap, length: length)
      rescue error
        ::Log::Metadata::Value.new("#<to_trace raised #{error.class}>")
      end
    end
  end
end
