# Detail levels: how much of the arguments and results a trace shows, set per
# method with `@[Logged]` and per field with `@[LogAs]`, and the limits
# `@[LogAs]` sets for one value.
#
#   crystal run examples/detail_levels.cr

require "../src/logbuch"
# Required after logbuch, which finds the value types all the same.
require "uri"
require "uuid"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

class Customer
  # Shown from Id detail up.
  @[LogAs(:id)]
  getter id : String

  # Unannotated strings and numbers are shown from Summary up.
  getter name : String
  getter age : Int32

  # Unannotated objects and collections are shown only at Full.
  getter orders : Array(String)

  # Annotated fields are shown from their level up.
  @[LogAs(:full)]
  getter notes : String

  def initialize(@id : String, @name : String, @age : Int32, @orders : Array(String), @notes : String)
  end
end

# A struct without annotated fields is logged with `inspect`; `@[LogType]` on
# it would log it by its fields instead, as `Node` below shows.
struct Money
  getter cents : Int32
  getter currency : String

  def initialize(@cents : Int32, @currency : String)
  end
end

# A struct with at least one annotated field follows the field rules.
struct Address
  getter city : String

  @[LogAs(:full)]
  getter street : String

  def initialize(@city : String, @street : String)
  end
end

# Objects that refer back to themselves are cut off where they repeat, and
# logged there as their identity: without a field marked `:id`, their type and
# object id.
# `@[LogType]` logs a class by its fields although none is annotated; without
# it, the class would be logged with `inspect`.
@[LogType]
class Node
  getter name : String
  property next_node : Node? = nil

  def initialize(@name : String)
  end
end

# `@[LogAs]` can set limits of its own for one field or parameter, in place
# of the settings: `cap:` for a collection and `length:` for a string.
# `items(...)` sets them for each item of a collection. How deep the objects,
# structs and collections inside a value nest is the `max_depth` setting.
class Report
  @[LogAs(:summary, items(length: 5), cap: 2)]
  getter tags : Array(String)

  @[LogAs(:summary, length: 12)]
  getter title : String

  @[LogAs(:full)]
  getter route : Node

  @[LogAs(:full)]
  getter postage : Money

  def initialize(@tags : Array(String), @title : String, @route : Node, @postage : Money)
  end
end

class CustomerService
  @[Logged("looking up a customer", :id)]
  def find(customer : Customer) : Bool
    true
  end

  # :summary is the default detail.
  @[Logged("greeting a customer")]
  def greet(customer : Customer) : String
    "Hello #{customer.name}"
  end

  # The detail can also be a `Logbuch::Detail` member.
  @[Logged("auditing a customer", Logbuch::Detail::Full)]
  def audit(customer : Customer) : Bool
    true
  end

  # :omit traces the call without argument or result data.
  @[Logged("pinging a customer", :omit)]
  def ping(customer : Customer) : Bool
    true
  end

  # A parameter that sets its own detail is logged at it, whatever the
  # method's, even with :omit.
  @[Logged("phoning a customer", :omit)]
  def phone(customer : Customer, @[LogAs(:id)] agent : Customer) : Bool
    true
  end

  @[Logged("shipping a parcel", :full)]
  def ship(address : Address, postage : Money) : Bool
    true
  end

  # :id logs every object as its identity: without `@[LogAs(:id)]` fields, an
  # opted-in class shows its object id, an opted-in struct only its type, and
  # a type that did not opt in its `inspect` text, as at every other detail.
  @[Logged("tracking a parcel", :id)]
  def track(address : Address, postage : Money, route : Node) : Bool
    true
  end

  # Stdlib value types such as `UUID`, `URI` and `Time::Span` are their own
  # identity, so :id logs their text.
  @[Logged("following a parcel", :id)]
  def follow(parcel : UUID, page : URI, eta : Time::Span) : Bool
    true
  end

  @[Logged("walking a list", :full)]
  def walk(node : Node) : Int32
    1
  end

  # `items(...)` can take a converter for each item, here the initial of each
  # signer.
  @[Logged("filing a report", :full)]
  def file(
    report : Report,
    @[LogAs(length: 8)] comment : String,
    @[LogAs(items(converter: ->(signer : String) { "#{signer[0]}." }))] signers : Array(String),
  ) : Bool
    true
  end
end

service = CustomerService.new
customer = Customer.new("c-1", "Ada", 36, ["o-1", "o-2"], "prefers email")

puts "# :id shows the identity, made of the fields marked @[LogAs(:id)]:"
service.find(customer)

puts "\n# :summary (the default) adds strings and numbers:"
service.greet(customer)

puts "\n# :full adds objects, collections and fields marked @[LogAs(:full)]:"
service.audit(customer)

puts "\n# :omit traces the call without data:"
service.ping(customer)

puts "\n# ... except a parameter with a detail of its own:"
service.phone(customer, Customer.new("c-9", "Grace", 41, [] of String, "on call"))

puts "\n# A plain struct is logged with inspect, an annotated one by its fields:"
service.ship(Address.new("Berlin", "Main Street 1"), Money.new(495, "EUR"))

puts "\n# At :id, without @[LogAs(:id)] fields, opted-in classes show their object id, opted-in structs their type, others their inspect text:"
service.track(Address.new("Berlin", "Main Street 1"), Money.new(495, "EUR"), Node.new("depot"))

puts "\n# At :id, stdlib value types show their text, and a URI its password as ***:"
service.follow(UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8"), URI.parse("https://track:s3cret@example.com/parcels"), 90.minutes)

puts "\n# A cycle is cut off where the object repeats, which is logged as its identity:"
first = Node.new("first")
second = Node.new("second")
first.next_node = second
second.next_node = first
service.walk(first)

puts "\n# Limits on a field or a parameter cut that value, or with items(...) each of its items:"
market = Node.new("market")
market.next_node = Node.new("harbour")
route = Node.new("depot")
route.next_node = market
report = Report.new(["late", "damaged", "returned"], "Weekly delivery report", route, Money.new(495, "EUR"))
service.file(report, "all parcels arrived", ["Ada", "Grace"])
