# A program with its own `Logged`, at the top level and in a module. It
# writes logbuch's annotation by its full name or under an alias, and prints
# the message of each entry line.
require "../../../src/logbuch"

include Logbuch::Annotations

class PrintBackend < Log::Backend
  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    puts entry.message if entry.message.starts_with?(">")
  end
end

Log.setup(:trace, PrintBackend.new)

class Logged
  def self.kind : String
    "the program's Logged"
  end
end

alias Traced = Logbuch::Annotations::Logged

class Shop
  @[Traced]
  def place : Nil
  end

  @[Logbuch::Annotations::Logged]
  def cancel : Nil
  end
end

module MyApp
  class Logged
    def self.kind : String
      "MyApp's Logged"
    end
  end

  alias Traced = Logbuch::Annotations::Logged

  class Order
    @[Traced]
    def ship : Nil
    end
  end
end

# Outside the module, and with no top-level name in the way, the other short
# names still mean logbuch's.
class Plain
  @[Traced]
  @[LogError(:warn)]
  def go(@[LogAs(:redacted)] pin : String) : Nil
  end
end

puts Logged.kind, MyApp::Logged.kind
Shop.new.place
Shop.new.cancel
MyApp::Order.new.ship
Plain.new.go("1")
