# Custom conversions: a type decides how it is logged by defining `to_trace`.
# It receives a `Logbuch::Tracer`, which carries the detail and the limits,
# and converts the values inside with `tracer.convert`, so they get the
# limits, the cycle checks and the depth limit as any traced value does.
#
#   crystal run examples/to_trace.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

# Prints *value* as it is logged at *detail*.
def show(label : String, value, detail : Logbuch::Detail = :summary) : Nil
  puts "  #{label.ljust(22)} #{Logbuch.convert(value, detail: detail).inspect}"
end

# A struct logged as a hash of the values it converts.
struct Money
  def initialize(@cents : Int32, @currency : String)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"amount" => tracer.convert(@cents / 100), "currency" => tracer.convert(@currency)})
  end
end

# A value type of the program: its text is its value, logged at every
# detail and cut to the length limit the value has.
struct Sku
  def initialize(@code : String)
  end

  def to_s(io : IO) : Nil
    io << "SKU-" << @code
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    tracer.convert(to_s, length: tracer.length)
  end
end

# `tracer.detail` is the detail the value is logged at, so a type can log
# less at `:id`. `cap:` and `length:` set limits for one value inside.
class Product
  def initialize(@sku : Sku, @name : String, @tags : Array(String), @description : String)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    return tracer.convert(@sku) if tracer.detail.id?

    Log::Metadata::Value.new({
      "sku"         => tracer.convert(@sku),
      "name"        => tracer.convert(@name),
      "tags"        => tracer.convert(@tags, cap: 2),
      "description" => tracer.convert(@description, length: 12),
    })
  end
end

# With a block, `tracer.convert` converts what the block returns, the way a
# `converter:` on `@[LogAs]` does. If the block raises, that value shows a
# placeholder and the rest is logged as usual.
class Card
  def initialize(@holder : String, @number : String, @pin : String)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({
      "holder" => tracer.convert(@holder),
      "number" => tracer.convert(@number) { |number| "****#{number[-4..]}" },
      "pin"    => tracer.convert(@pin) { |pin| pin[10] },
    })
  end
end

# A `to_trace` that raises leaves a placeholder for the whole value being
# logged, such as a traced method's argument; the call runs as usual.
class Sensor
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    raise IO::Error.new("sensor offline")
  end
end

# An object with a `to_trace` of its own can contain itself; `tracer.convert`
# cuts the cycle, where the object is logged as its identity.
class Folder
  getter children = [] of Folder

  def initialize(@name : String)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"name" => tracer.convert(@name), "children" => tracer.convert(@children)})
  end
end

class Shop
  @[Logged("adding a product")]
  def add(product : Product, price : Money) : Sku
    Sku.new("1042")
  end

  @[Logged("finding a product", :id)]
  def find(product : Product) : Bool
    true
  end
end

product = Product.new(Sku.new("1042"), "Kettle", ["kitchen", "steel", "sale"], "A kettle that whistles when the water boils")

puts "# A struct converts its values into a hash, a value type into its text:"
show "Money", Money.new(1999, "EUR")
show "Sku", Sku.new("1042")

puts "\n# tracer.detail picks what to show, cap: and length: limit one value inside:"
show "Product at :summary", product
show "Product at :id", product, :id

puts "\n# A block converts what it returns; one that raises leaves a placeholder:"
show "Card", Card.new("Ada", "4111222233334444", "1234")

puts "\n# A to_trace that raises leaves a placeholder for the whole value being logged:"
show "Sensor", Sensor.new
show "Sensor in a tuple", {Sensor.new, "kitchen"}

puts "\n# A cycle is cut where the folder repeats:"
root = Folder.new("root")
root.children << Folder.new("docs") << root
show "Folder", root

puts "\n# In a trace line, arguments and results convert the same way:"
shop = Shop.new
shop.add(product, Money.new(1999, "EUR"))
shop.find(product)
