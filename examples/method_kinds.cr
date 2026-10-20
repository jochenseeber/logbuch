# Method kinds: class methods, blocks, splats, external names, generics,
# structs, modules, private methods and subclasses, with `super`, are all
# traced the same way.
#
#   crystal run examples/method_kinds.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

module Inventory
  # Every traced type in this module logs to the "inventory" source.
  Log = ::Log.for("inventory")

  class Store
    getter name : String

    def initialize(@name : String)
    end

    # Class methods are named Type.method.
    @[Logged("opening a store")]
    def self.open(name : String) : Store
      new(name)
    end

    # The caller's block runs unchanged, including next and break.
    @[Logged("listing the items")]
    def each_item(&) : Nil
      yield "apple", 3
      yield "pear", 0
      yield "plum", 5
    end

    # Splats and double splats are logged under their names.
    @[Logged("restocking")]
    def restock(*items : String, **counts) : Int32
      items.size + counts.size
    end

    # A captured block is passed on, too.
    @[Logged("checking the stock")]
    def check(item : String, &rule : String -> Bool) : Bool
      rule.call(item)
    end

    def audit : Int32
      secret_count
    end

    # Private methods stay private and are traced.
    @[Logged("counting secretly")]
    private def secret_count : Int32
      42
    end

    # An external name, a named-only parameter and a default value: the
    # arguments are logged under their internal names.
    @[Logged("selling an item")]
    def sell(item : String, for price : Int32, *, receipt : Bool = true) : String
      "#{item} for #{price}"
    end

    # Generic methods (`forall`) too.
    @[Logged("labelling a value")]
    def label(value : T) : String forall T
      "#{T}: #{value}"
    end
  end

  # A subclass's own traced methods are logged under its name; the methods it
  # inherits from Store keep Store's name.
  class Kiosk < Store
    @[Logged("selling a newspaper")]
    def sell_newspaper : String
      "Daily News"
    end

    # An override with a `@[Logged]` of its own is logged under Kiosk's name.
    # When it calls the traced Store#sell with `super`, only the outer call is
    # logged.
    @[Logged("selling at the kiosk")]
    def sell(item : String, for price : Int32, *, receipt : Bool = true) : String
      super
    end
  end

  # In a module, the traced methods are wrapped in the module itself, so they
  # are traced wherever they are called: through `extend self` or through a
  # class that includes the module. They keep the module's name.
  module Pricing
    extend self

    @[Logged("pricing an item")]
    def price(item : String) : Int32
      item.size
    end
  end

  class Till
    include Pricing
  end

  # Generic types get the label without type arguments.
  class Shelf(T)
    def initialize(@items : Array(T))
    end

    @[Logged("taking the first item")]
    def first : T
      @items.first
    end
  end

  # Structs work like classes.
  struct Barcode
    def initialize(@code : String)
    end

    @[Logged("scanning a barcode")]
    def scan : String
      @code
    end
  end
end

# A private type is the one that includes Logbuch::Annotations itself:
# logbuch cannot reopen it from outside this file to add the tracing.
private class Ledger
  include Logbuch::Annotations

  @[Logged("adding up the ledger")]
  def total(amounts : Array(Int32)) : Int32
    amounts.sum
  end
end

puts "# A class method:"
store = Inventory::Store.open("Corner Shop")

puts "\n# Blocks work as usual; break still writes the exit line:"
store.each_item do |item, count|
  next if count == 0
  puts "  #{item}: #{count}"
end
found = store.each_item { |item, _| break item if item.starts_with?("p") }
puts "  found #{found}"

puts "\n# Splats and double splats:"
store.restock("apple", "pear", apples: 10, pears: 5)

puts "\n# A captured block:"
store.check("plum", &.size.>(3))

puts "\n# A private method called from inside:"
store.audit

puts "\n# External names, named-only parameters and defaults; a generic method:"
store.sell("apple", for: 3)
store.label(:fresh)

puts "\n# A subclass, a generic type and a struct:"
kiosk = Inventory::Kiosk.new("Station Kiosk")
kiosk.sell_newspaper
Inventory::Shelf(String).new(["tea", "coffee"]).first
Inventory::Barcode.new("4006381333931").scan

puts "\n# An inherited method keeps the name of the type that defines it:"
kiosk.audit

puts "\n# An override that calls super logs only the outer call:"
kiosk.sell("map", for: 7, receipt: false)

puts "\n# A module's traced method, through extend self and through an including class:"
Inventory::Pricing.price("pear")
Inventory::Till.new.price("plum")

puts "\n# A private type with its own include:"
Ledger.new.total([3, 4])
