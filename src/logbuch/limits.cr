require "array"
require "exception"
require "hash"
require "int"
require "io"
require "log"
require "pointer"
require "slice"
require "string"

module Logbuch
  # Nesting depth of objects, structs and collections in one traced value;
  # deeper ones are logged as their identity, such as `"o-17"`. See
  # `Tracer` for the values that take a level.
  MAX_DEPTH = 16_u32

  # The deepest any traced value nests, also through a `Logbuch.convert` in a
  # `to_trace`, so converting it neither overflows the stack nor grows the
  # tracer's path without bound. A `max_depth` above it fails to compile or
  # raises.
  DEPTH_CEILING = 256_u32

  # Items logged from one collection; the rest are counted.
  MAX_CAP = 100_u32

  # Characters logged from one string; the rest are counted.
  MAX_LENGTH = 1024_u32

  # :nodoc:
  #
  # Converts the first items of *collection*, which has *size* items, as many
  # as the cap of *tracer* allows, each as the block returns it, then a count
  # of the rest.
  def self.__items(collection, size : Int, tracer : Tracer, &) : ::Log::Metadata::Value
    limit = tracer.cap
    # A limit below the size fits the size's type.
    items = Array(::Log::Metadata::Value).new((size < limit ? size : limit.to_i32) + 1)
    collection.each do |item|
      break if items.size == limit
      items << yield item
    end
    items << ::Log::Metadata::Value.new("… #{size - limit} more") if size > limit
    ::Log::Metadata::Value.new(items)
  end

  # `LimitedIO` is an `IO`, so a program that writes to an `IO` it does not
  # know the type of, as `p` does, compiles its `write`, whether it uses it or
  # not. With `-Dlogbuch=off` it is left out, and `__limited` cuts the text
  # after it is written instead.
  {% unless %w[off 0].includes?(flag?(:logbuch)) %}
    # :nodoc:
    #
    # Raised by `LimitedIO` at the first character past its limit.
    class LengthReached < Exception
    end

    # :nodoc:
    #
    # A write-only `IO` that keeps the first *limit* characters written to it
    # and raises `LengthReached` at the first character past them, which stops
    # whatever is writing, such as an `inspect` walking a deep object graph. It
    # remembers the cut itself, so the text is marked as cut even when the
    # writer rescues `LengthReached` and returns normally.
    class LimitedIO < IO
      # The call stack `LengthReached` is raised with: none, because capturing
      # one costs more than the rest of the cut.
      NO_CALL_STACK = Exception::CallStack.new([] of Void*)

      @buffer = String::Builder.new
      @chars = 0_u32
      @cut = false

      def initialize(@limit : UInt32)
      end

      def read(slice : Bytes) : NoReturn
        raise IO::Error.new("LimitedIO is write-only")
      end

      def write(slice : Bytes) : Nil
        chars = Logbuch.__chars(slice)
        if @chars + chars <= @limit
          @buffer.write(slice)
          @chars += chars
        else
          @buffer.write(slice[0, Logbuch.__char_offset(slice, @limit - @chars)])
          @chars = @limit
          @cut = true
          error = LengthReached.new
          error.callstack = NO_CALL_STACK
          raise error
        end
      end

      # The text written so far, ending in `…` when it was cut. Call it once.
      def finish : String
        @buffer << "…" if @cut
        @buffer.to_s
      end
    end
  {% end %}

  # :nodoc:
  #
  # The text the block writes to the `IO` it is given, cut to *limit*
  # characters. Writing stops at the limit, so a large or deep value costs no
  # more than the text that is kept. Cut text ends in `…`; the rest was never
  # written, so it is not counted. With `-Dlogbuch=off`, which leaves out
  # `LimitedIO`, the block writes the whole text, which is cut to the same
  # result afterwards.
  def self.__limited(limit : UInt32, & : IO ->) : String
    {% if %w[off 0].includes?(flag?(:logbuch)) %}
      __cut(String.build { |io| yield io }, limit)
    {% else %}
      io = LimitedIO.new(limit)
      begin
        yield io
      rescue LengthReached
        # The text up to the limit is in *io*, which marks it as cut.
      end
      io.finish
    {% end %}
  end

  # :nodoc:
  #
  # *text* cut to *limit* characters, ending in `…` when it was cut, as
  # `__limited` cuts the text written to it.
  def self.__cut(text : String, limit : UInt32) : String
    return text if text.bytesize <= limit
    bytes = text.to_slice
    cut = __char_offset(bytes, limit)
    return text if cut == bytes.size
    String.build(cut + 3) do |io|
      io.write(bytes[0, cut])
      io << '…'
    end
  end

  # :nodoc:
  #
  # The `inspect` text of *value*, cut to *limit* characters by `__limited`:
  # `inspect` stops writing at the limit, so a large or deep object costs no
  # more than the text that is logged.
  def self.__inspect(value, limit : UInt32) : String
    __limited(limit) { |io| value.inspect(io) }
  end

  # :nodoc:
  #
  # Cuts *text* to *limit* characters and counts the bytes left. Only the
  # characters up to the limit are looked at, so a long string costs no more
  # than a short one; counting the characters left would mean reading them
  # all.
  def self.__truncate(text : String, limit : UInt32) : String
    return text if text.bytesize <= limit
    bytes = text.to_slice
    # A string that knows it is ASCII has as many characters as bytes.
    cut = text.@length == bytes.size ? limit : __char_offset(bytes, limit)
    return text if cut == bytes.size
    String.build(cut + 24) do |io|
      io.write(bytes[0, cut])
      io << "… (+" << (bytes.size - cut) << " bytes)"
    end
  end

  # :nodoc:
  #
  # The `to_s` text of *value*, cut to *limit* characters like `__inspect`:
  # `to_s` stops writing at the limit, and cut text ends in `…`.
  def self.__text(value, limit : UInt32) : String
    __limited(limit) { |io| value.to_s(io) }
  end

  # :nodoc:
  #
  # The number of characters in *bytes*, which hold UTF-8: the bytes that
  # start a character, that is, all but the continuation bytes `0b10xxxxxx`.
  # The loop has no branch, so the compiler vectorizes it.
  def self.__chars(bytes : Bytes) : UInt32
    pointer = bytes.to_unsafe
    count = 0_u32
    bytes.size.times do |index|
      byte = pointer[index]
      count &+= (((byte >> 7) ^ 1) | ((byte >> 6) & 1)).to_u32
    end
    count
  end

  # :nodoc:
  #
  # The byte offset in *bytes* where character *index* (from 0) starts, or the
  # size of *bytes* when it holds no more characters.
  def self.__char_offset(bytes : Bytes, index : UInt32) : UInt32
    seen = 0_u32
    bytes.each_with_index do |byte, offset|
      next if byte & 0xC0 == 0x80
      return offset.to_u32 if seen == index
      seen += 1
    end
    bytes.size.to_u32
  end
end
