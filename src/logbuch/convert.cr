require "exception"
require "log"

require "./detail"
require "./fiber_state"
require "./fields"
require "./tracer"
require "./values"

module Logbuch
  # Converts *value* into trace data at *detail*, as a traced method logs it.
  # At `Detail::Omit` it converts to nil.
  #
  # ```
  # Logbuch.convert(order, detail: :full)
  # ```
  def self.convert(value, *, detail : Detail = Detail::Summary) : ::Log::Metadata::Value
    __convert(value, detail)
  end

  # :nodoc:
  #
  # Converts an argument or a result for a trace line, with the limits its
  # annotation sets. A conversion must not change what a traced method does,
  # so if `to_trace` raises, the line gets a placeholder naming the exception
  # class instead.
  def self.__convert(value, detail : Detail, *, cap : UInt32? = nil, length : UInt32? = nil) : ::Log::Metadata::Value
    return ::Log::Metadata::Value.new(nil) if detail.omit?
    Tracer.use(detail) { |tracer| tracer.convert(value, cap: cap, length: length) }
  rescue error
    ::Log::Metadata::Value.new("#<to_trace raised #{error.class}>")
  end

  # :nodoc:
  #
  # Converts what a `converter:` block returns for *value*, like the other
  # overload. The block runs before the conversion starts, so a traced method
  # it calls logs with a tracer of its own. If it raises, the line gets a
  # placeholder naming the exception class.
  def self.__convert(value, detail : Detail, *, cap : UInt32? = nil, length : UInt32? = nil, &) : ::Log::Metadata::Value
    converted = begin
      yield value
    rescue error
      return ::Log::Metadata::Value.new("#<convert raised #{error.class}>")
    end
    __convert(converted, detail, cap: cap, length: length)
  end

  # :nodoc:
  #
  # Converts an argument for a trace line like `__convert`, and each item of
  # it with the options of its `items(...)`, as `Tracer#__convert_items`
  # does: the block, the item converter, runs during the conversion.
  def self.__convert_items(value, detail : Detail, *, cap : UInt32? = nil, length : UInt32? = nil, item_detail : Detail? = nil, item_cap : UInt32? = nil, item_length : UInt32? = nil, &) : ::Log::Metadata::Value
    return ::Log::Metadata::Value.new(nil) if detail.omit?
    Tracer.use(detail) do |tracer|
      tracer.__convert_items(value, cap: cap, length: length, item_detail: item_detail, item_cap: item_cap, item_length: item_length) { |item| yield item }
    end
  rescue error
    ::Log::Metadata::Value.new("#<to_trace raised #{error.class}>")
  end
end
