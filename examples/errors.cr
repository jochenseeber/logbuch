# Error lines and stack traces: the error line where an exception first
# appears has the exception attached, which a formatter prints with its stack
# trace; `stacktrace: false` leaves it out for expected failures, on the
# exception type's `@[LogType]` or on a method's `@[LogError]`, which also sets
# the level of the error line. `@[LogAccept]` logs expected exceptions as the
# result instead, and either annotation traces a method without `@[Logged]`.
#
#   crystal run examples/errors.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

# The stdlib formatters print an attached exception with its whole stack
# trace. Its frames change from build to build, so this formatter only notes
# that one is attached.
struct ExampleFormat < Log::StaticFormatter
  def run
    severity
    string " "
    message
    data(before: " -- ")
    string " [stack trace of #{@entry.exception.class}]" if @entry.exception
  end
end

Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

# An expected failure: its error lines never carry the stack trace.
@[LogType(stacktrace: false)]
class OutOfStock < Exception
end

# A subclass inherits that, unless it sets `stacktrace: true` again.
@[LogType(stacktrace: true)]
class Discontinued < OutOfStock
end

class Shop
  @[Logged("reserving an item")]
  def reserve(item : String) : Nil
    raise OutOfStock.new("no #{item} left") if item == "kettle"
    raise Discontinued.new("#{item} is discontinued") if item == "toaster"
    raise ArgumentError.new("unknown item #{item}")
  end

  # A method can decide for itself; the most specific type wins, and a
  # `LogError` overrides what the exception type says. Error lines are written
  # at :error unless a `LogError` names another level.
  @[Logged("loading the catalog")]
  @[LogError(IO::Error, :warn, stacktrace: false)]
  @[LogError(IO::TimeoutError, OutOfStock, stacktrace: true)]
  def load(source : String) : Nil
    raise IO::TimeoutError.new("#{source} timed out") if source == "remote"
    raise OutOfStock.new("catalog is empty") if source == "empty"
    raise IO::Error.new("#{source} is closed")
  end

  # The call where an exception first appears decides: here `reserve`, so
  # `checkout` logs only the exception's type.
  @[Logged("checking out")]
  def checkout(item : String) : Nil
    reserve(item)
  end

  # A `LogError` without types applies to every exception the others do not
  # list. The level can also be a `Log::Severity` member. Without `@[Logged]`,
  # a `LogError` traces the method on its own, so the messages are its name.
  @[LogError(KeyError, Log::Severity::Info, stacktrace: false)]
  @[LogError(:warn)]
  def restock(item : String) : Nil
    raise KeyError.new("no shelf for #{item}") if item == "kettle"
    raise Exception.new("cannot restock #{item}", cause: IO::Error.new("supplier offline"))
  end

  # Expected outcomes are logged as the result, at the method's level or the
  # one the `LogAccept` names; `stacktrace: true` attaches the exception to the
  # exit line. The most specific type wins, and the method still raises it.
  @[Logged("looking up a price")]
  @[LogAccept(IO::Error, :info)]
  @[LogAccept(IO::TimeoutError, :warn, stacktrace: true)]
  def price(item : String) : Int32
    raise IO::TimeoutError.new("price list timed out") if item == "lamp"
    raise IO::Error.new("price list is closed")
  end

  # A `LogAccept` alone traces the method too.
  @[LogAccept(KeyError)]
  def stock(item : String) : Int32
    {"kettle" => 3}[item]
  end

  # A caller that does not accept the exception writes an error line with
  # only its type, since `stock` logged it in full as its result.
  @[Logged("counting the stock")]
  def count(item : String) : Int32
    stock(item)
  end
end

shop = Shop.new

def attempt(&) : Nil
  yield
rescue
end

puts "# An unexpected error carries its stack trace."
attempt { shop.reserve("lamp") }

puts "\n# OutOfStock has stacktrace: false, so its error line carries none."
attempt { shop.reserve("kettle") }

puts "\n# Discontinued sets stacktrace: true again."
attempt { shop.reserve("toaster") }

puts "\n# The method's LogError writes IO::Error at warn, without the stack trace ..."
attempt { shop.load("file") }

puts "\n# ... keeps the stack trace and :error for the more specific IO::TimeoutError ..."
attempt { shop.load("remote") }

puts "\n# ... and turns it back on for OutOfStock."
attempt { shop.load("empty") }

puts "\n# A caller further up logs only the type."
attempt { shop.checkout("kettle") }

puts "\n# A LogError alone traces the method; KeyError is written at info, without the stack trace ..."
attempt { shop.restock("kettle") }

puts "\n# ... and any other exception at warn, here with its cause:"
attempt { shop.restock("lamp") }

puts "\n# An accepted IO::Error is the result, on an exit line at info ..."
attempt { shop.price("kettle") }

puts "\n# ... and the more specific IO::TimeoutError is, at warn, with its stack trace."
attempt { shop.price("lamp") }

puts "\n# A LogAccept alone traces the method; a caller that does not accept the"
puts "# exception logs only its type."
attempt { shop.count("lamp") }
