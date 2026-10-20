# Structured output: the trace data is `Log::Metadata`, so a backend can write
# it as JSON, with nested arguments kept as nested objects, and another
# backend can read single values by the keys in `Logbuch::Keys`.
#
#   crystal run examples/json_logging.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

# After `log`, which logbuch loads: adds `to_json` to log data.
require "json"
require "log/json"

# Writes each log entry as one line of JSON.
class JsonBackend < Log::Backend
  def initialize(@io : IO = STDOUT)
    super(:sync)
  end

  def write(entry : Log::Entry) : Nil
    JSON.build(@io) do |json|
      json.object do
        json.field "severity", entry.severity.label
        json.field "source", entry.source
        json.field "message", entry.message
        json.field("data") { entry.data.to_json(json) }
      end
    end
    @io.puts
  end
end

# Counts the error lines by exception type. `Logbuch::Keys` names the keys of
# the trace data, for code that reads the lines.
class ErrorTally < Log::Backend
  getter counts = Hash(String, Int32).new(0)

  def initialize
    super(:sync)
  end

  def write(entry : Log::Entry) : Nil
    return unless error = entry.data[Logbuch::Keys::ERROR]?
    counts[error.as_h[Logbuch::Keys::TYPE].as_s] += 1
  end
end

tally = ErrorTally.new

Log.setup do |config|
  config.bind "*", :trace, JsonBackend.new
  config.bind "*", :trace, tally
end

class Order
  @[LogAs(:id)]
  getter id : String = "o-17"
  getter total : Int32 = 4200
  getter items : Array(String) = ["book", "pen"]
end

class Checkout
  @[Logged("placing an order", :full)]
  def place(order : Order, @[LogAs(:redacted)] coupon : String) : String
    "receipt-#{order.id}"
  end

  @[Logged("paying an order")]
  def pay(order : Order) : Nil
    raise Exception.new("payment declined", cause: IO::Error.new("bank unreachable"))
  end
end

checkout = Checkout.new
checkout.place(Order.new, "SPRING-SALE")

# The error and its cause are nested objects too.
2.times do
  checkout.pay(Order.new)
rescue
end

puts "errors by type: #{tally.counts}"
