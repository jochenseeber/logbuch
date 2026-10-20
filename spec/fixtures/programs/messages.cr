require "../../../src/logbuch"

# Prints the message of each trace line, one per line.
Log.define_formatter MessageOnly, "#{message}"
Log.setup(:trace, Log::IOBackend.new(formatter: MessageOnly, dispatcher: :sync))

# How often the exit message converter's expansion ran, by label.
EXIT_BUILDS = Hash(String, Int32).new(0)

module Shop
  class Checkout
    include Logbuch::Annotations

    @[Logged("placing the order")]
    def place(order : String, using coupon : String) : String
      "#{order}-#{coupon}"
    end

    @[Logged(:debug)]
    def bulk(@[LogAs(:omit)] first : Int32, *rest : Int32, @[LogAs(:redacted)] key : String = "k", **options, &block : Int32 -> Int32) : Int32
      block.call(first)
    end

    @[Logged]
    def split(a : Int32, *, b : Int32) : Int32
      a + b
    end

    @[Logged]
    def each(&) : Nil
      yield 1
    end

    @[Logged("building a checkout")]
    def self.build : Checkout
      new
    end

    @[Logged("failing")]
    def fail : Nil
      raise ArgumentError.new("no")
    end
  end
end

class Pallet(T)
  include Logbuch::Annotations

  @[Logged]
  def get(value : T) : T
    value
  end
end

# The converters are replaced after the traced types: the wrappers are
# generated once the whole program is read, so the last definition wins.
module Logbuch::Messages
  macro entry_message(call)
    {{ "#{call[:type].id}|#{call[:method].id}|#{call[:class_method]}|#{call[:label].id}|#{call[:description]}|#{call[:level].id}|#{call[:params].join(",").id}" }}
  end

  # A computed message, built the first time it is read.
  macro exit_message(call)
    begin
      ::EXIT_BUILDS[{{ call[:label] }}] += 1
      {{ call[:label] }}.upcase
    end
  end
end

checkout = Shop::Checkout.build
checkout.place("o-1", "c-1")
checkout.place("o-2", "c-2")
checkout.bulk(1, 2, 3, key: "k", extra: true) { |value| value }
checkout.split(1, b: 2)
checkout.each { }
Pallet(Int32).new.get(1)
begin
  checkout.fail
rescue ArgumentError
end
puts "exit builds: #{EXIT_BUILDS.to_a.sort.map { |label, count| "#{label}=#{count}" }.join(", ")}"
