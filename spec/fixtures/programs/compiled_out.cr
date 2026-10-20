# build: --release --no-debug
#
# A program that uses every annotation and `Logbuch.configure`, but converts
# nothing itself. Built with `-Dlogbuch=off`, its binary holds nothing of the
# shard, which its spec checks by looking for the shard's name in it. It is
# built for release, as such a program would be shipped, and without debug
# information, which names every type, also those that generate no code.
require "../../../src/logbuch"

include Logbuch::Annotations

@[LogType(stacktrace: false)]
class OutOfStock < Exception
end

@[LogType]
class Order
  @[LogAs(:id)]
  getter number : String

  @[LogAs(:redacted)]
  getter card : String

  def initialize(@number : String, @card : String)
  end
end

struct Line
  @[LogAs(:full, cap: 3)]
  getter items : Array(String)

  def initialize(@items : Array(String))
  end
end

class Shop
  @lock = Sync::Mutex.new

  @[Logged(:full, timing: true, slow: {ms: 100, level: :warn})]
  @[LogError(:warn, stacktrace: false)]
  def place(order : Order, @[LogAs(:summary, length: 8)] note : String) : Int32
    order.number.size + note.size
  end

  @[Logged(lock: @lock, result: ->(lines : Array(Line)) { lines.size })]
  def lines : Array(Line)
    [Line.new(["a", "b"])]
  end

  @[Logged]
  @[LogAccept(OutOfStock)]
  def reserve(count : Int32) : Int32
    raise OutOfStock.new("none left") if count > 3
    count
  end
end

module Prices
  @[Logged(:id)]
  def self.total(amounts : Array(Int32)) : Int32
    amounts.sum
  end
end

Logbuch.configure do
  max_depth 3
  max_cap 5
  max_length 80
end

# Writes through an `IO` of any type, which compiles `write` for every `IO`
# subclass in the program.
output : IO = STDOUT

shop = Shop.new
output.puts shop.place(Order.new("o-1", "4111"), "leave it at the door")
output.puts shop.lines.size
output.puts shop.reserve(2)
begin
  shop.reserve(5)
rescue error : OutOfStock
  output.puts error.message
end
output.puts Prices.total([1, 2, 3])
