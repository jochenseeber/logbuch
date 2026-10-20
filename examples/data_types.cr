# Data types: how each kind of value is logged, from numbers and strings to
# tuples, objects, collections and the value types of the standard library.
# Each line shows a value as `Logbuch.convert` turns it into log data, which
# is what a traced method logs for its arguments and its result. The last
# section shows the `inspect` logbuch writes for annotated types.
#
#   crystal run examples/data_types.cr

require "../src/logbuch"
# Standard library types logbuch logs by their text once the program has them.
require "big"
require "semantic_version"
require "socket"
require "uri"
require "uuid"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

# Smaller limits than the defaults, so the cut values below stay short.
Logbuch.configure do
  max_cap 4
  max_length 40
end

# Prints *value* as it is logged at *detail*.
def show(label : String, value, detail : Logbuch::Detail = :summary) : Nil
  puts "  #{label.ljust(22)} #{Logbuch.convert(value, detail: detail).inspect}"
end

# Prints the `inspect` text of *value*.
def show_inspect(label : String, value) : Nil
  puts "  #{label.ljust(22)} #{value.inspect}"
end

enum Color
  Red
  Green
end

# A record logged with `inspect`: it has not opted in to field logging.
record Point, x : Int32, y : Int32

# A class that has not opted in: logged with `inspect`, address included.
class Plain
  @name = "plain"
end

# A class logged by its fields. Strings, numbers and structs show from
# `:summary`, other objects and collections only at `:full`, and `@[LogAs]`
# sets a field's own detail.
@[LogType]
class Order
  @[LogAs(:id)]
  getter id = "o-17"
  getter total = 42
  getter items = ["book", "pen"]
  getter shipped_to = Point.new(1, 2)

  @[LogAs(:redacted)]
  getter coupon = "SAVE10"
end

# A class whose orders log at a detail of their own: `items(...)` sets how
# each item of a collection is logged, apart from the collection: its detail,
# its limits and a converter. `cap:` next to it limits the collection itself.
@[LogType]
class Customer
  getter name = "Ada"

  @[LogAs(:summary, items(:id))]
  getter orders = [Order.new]

  @[LogAs(:summary, items(length: 8), cap: 2)]
  getter notes = ["prefers email", "pays early", "VIP"]
end

# A small object logged by its fields, used as a hash key below.
@[LogType]
class Account
  @[LogAs(:id)]
  getter id : String

  @[LogAs(:redacted)]
  getter password = "hunter2"

  def initialize(@id : String)
  end
end

# An object that refers to itself, cut where it repeats and logged there as
# its identity, which shows its `:id` field.
@[LogType]
class Node
  @[LogAs(:id)]
  getter name : String
  property next_node : Node? = nil

  def initialize(@name : String)
  end
end

# A class without an `:id` field: its identity shows its object id.
@[LogType]
class Visitor
  getter name = "Ada"
end

# A class with two `:id` fields: its identity shows both.
@[LogType]
class Seat
  @[LogAs(:id)]
  getter row : Int32
  @[LogAs(:id)]
  getter letter : String
  getter price = 45

  def initialize(@row : Int32, @letter : String)
  end
end

# A struct without an `:id` field: its identity is its type only, so nothing
# of the redacted pin can show.
@[LogType]
struct Badge
  getter holder : String
  @[LogAs(:redacted)]
  getter pin : String

  def initialize(@holder : String, @pin : String)
  end
end

# A struct with one `:id` field.
@[LogType]
struct Pass
  @[LogAs(:id)]
  getter code : String
  getter zone = "A"

  def initialize(@code : String)
  end
end

# A struct whose one `:id` field holds an object, which shows as its own
# identity.
@[LogType]
struct Ticket
  @[LogAs(:id)]
  getter seat : Seat
  getter gate = "B"

  def initialize(@seat : Seat)
  end
end

# A struct with two `:id` fields.
@[LogType]
struct Slot
  @[LogAs(:id)]
  getter day : String
  @[LogAs(:id)]
  getter hour : Int32

  def initialize(@day : String, @hour : Int32)
  end
end

# `inspect: :full` shows the fields shown at :full too, here the cards.
@[LogType(inspect: :full)]
class Wallet
  getter owner = "Ada"
  getter cards = ["visa", "amex"]
  @[LogAs(:redacted)]
  getter pin = "1234"
end

# `inspect: :id` shows only the `:id` fields.
@[LogType(inspect: :id)]
struct Locker
  @[LogAs(:id)]
  getter number = 12
  getter contents = "coat"
end

# `inspect: :off` keeps Crystal's `inspect`, which shows every field.
@[LogType(inspect: :off)]
struct Diary
  @[LogAs(:redacted)]
  getter entry = "dear diary"
end

# Not opted in: its `inspect` shows every field, and the badge inside masks
# itself.
struct Envelope
  getter badge = Badge.new("Ada", "1234")
end

# An `inspect` of its own wins over logbuch's.
@[LogType]
class Receipt
  @[LogAs(:redacted)]
  getter total = 42

  def inspect(io : IO) : Nil
    io << "receipt r-1"
  end
end

class Shop
  @[Logged("placing an order", :full)]
  def place(order : Order, quantity : Int32, note : String?, tags : Set(Symbol)) : {Bool, String}
    {true, "receipt-#{order.id}"}
  end
end

puts "# Numbers, Bool, nil, Char, symbols and enums keep their value:"
show "Int32", 42
show "Int64", 9_000_000_000_i64
show "UInt8", 255_u8
show "Float64", 3.25
show "Bool", true
show "nil", nil
show "Char", 'x'
show "Symbol", :ready
show "enum", Color::Green
show "BigInt", BigInt.new("123456789012345678901234567890")

puts "\n# Strings are cut to the length limit, with the bytes left counted:"
show "short", "hello"
show "long", "a long text " * 10

puts "\n# Tuples and named tuples are logged whole, as arrays and objects:"
show "Tuple", {1, "two", :three}
show "NamedTuple", {id: 7, name: "Ada"}

puts "\n# Arrays, sets and deques are cut to the item limit, the rest counted:"
show "Array", [1, 2, 3]
show "long Array", (1..10).to_a
show "Set", Set{:a, :b}
show "Deque", Deque{1.5, 2.5}
show "Bytes", Bytes[1, 2, 3]

puts "\n# A hash is logged as [[key, value], …] pairs, cut to the item limit:"
show "String keys", {"name" => "Ada", "age" => 36}
show "Symbol keys", {:ok => 1, :failed => 0}
show "Int keys", {1 => "one", 2 => "two"}
show "long Hash", (1..10).to_h { |i| {i, i * i} }

puts "\n# Keys are logged at :id, so an object shows its identity, and keys of one text keep both entries:"
show "record keys", {Point.new(0, 0) => "origin", Point.new(1, 2) => "home"}
show "tuple keys", { {1, :a} => "first", {2, :b} => "second" }
show "object keys", {Account.new("a1") => "admin", Account.new("b2") => "guest"}
show "object keys at :id", {Account.new("a1") => "admin"}, :id
show "two :id fields", {Seat.new(12, "A") => "window", Seat.new(12, "B") => "aisle"}
show "object in :id field", {Ticket.new(Seat.new(12, "A")) => "booked"}
show "no :id field", {Badge.new("Ada", "1234") => "staff"}
show "keys of one text", {Badge.new("Ada", "1234") => "staff", Badge.new("Bob", "5678") => "guest"}
show "1 and \"1\"", {1 => "number", "1" => "string"} of Int32 | String => String
show "stdlib keys", {URI.parse("https://ann:secret@example.com") => 1, Path["/srv"] => 2}

puts "\n# Objects that have not opted in are logged with inspect:"
show "record", Point.new(3, 4)
show "class", Plain.new

puts "\n# An object logged by its fields, at each detail:"
show "Order at :id", Order.new, :id
show "Order at :summary", Order.new, :summary
show "Order at :full", Order.new, :full

puts "\n# items(...) logs the items of a collection at a detail and with limits of their own:"
show "Customer at :summary", Customer.new, :summary
show "Customer at :full", Customer.new, :full

head = Node.new("a")
tail = Node.new("b")
head.next_node = tail
tail.next_node = head
show "cycle", head, :full

puts "\n# At :id, in a cycle and past the depth limit, an object is its identity:"
show "class, no :id field", Visitor.new, :id
show "class, one :id field", Account.new("a1"), :id
show "class, two :id fields", Seat.new(12, "A"), :id
show "the same at :summary", Seat.new(12, "A")
show "struct, no :id field", Badge.new("Ada", "1234"), :id
show "struct, one :id field", Pass.new("p-7"), :id
show "struct, two :id fields", Slot.new("Mon", 9), :id
show "the same at :summary", Badge.new("Ada", "1234")
show "object in :id field", Ticket.new(Seat.new(12, "A")), :id

puts "\n# Standard library value types are logged as their text:"
show "URI", URI.parse("https://ann:secret@example.com/a?b=c")
show "UUID", UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
show "Path", Path["/srv/app"]
show "Time", Time.utc(2026, 10, 20, 9, 30)
show "Time::Span", 90.seconds
show "Socket::IPAddress", Socket::IPAddress.new("127.0.0.1", 8080)
show "SemanticVersion", SemanticVersion.parse("1.2.3-rc.1")
show "BigDecimal", BigDecimal.new("12.50")

puts "\n# An exception is logged with its type, message and cause:"
show "exception", Exception.new("bad input", cause: IO::Error.new("closed"))

puts "\n# inspect of an opted-in type shows its :summary fields, redacted ones as ***:"
show_inspect "class", Order.new
show_inspect "struct", Badge.new("Ada", "1234")
show_inspect "inspect: :full", Wallet.new
show_inspect "inspect: :id", Locker.new
show_inspect "inspect: :off", Diary.new
show_inspect "inside a plain type", Envelope.new
show_inspect "own inspect", Receipt.new
puts "  #{"pp".ljust(22)} #{String.build { |io| PrettyPrint.format(Badge.new("Ada", "1234"), io, 79) }}"

puts "\n# In a trace line, the arguments and the result are converted the same way:"
Shop.new.place(Order.new, 2, nil, Set{:gift, :express})
