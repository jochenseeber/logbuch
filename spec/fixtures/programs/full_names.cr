# A program that defines its own top-level `Logged` and `LogError`, with a
# shard in it that uses logbuch by the full names. logbuch adds no top-level
# names, so both work side by side. Prints each line's message and arguments.
require "../../../src/logbuch"

class PrintBackend < Log::Backend
  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    puts "#{entry.severity.label} #{entry.message} #{entry.data[:args]? || entry.data[:error]?.try(&.as_h["type"])}"
  end
end

Log.setup(:trace, PrintBackend.new)

# Stands in for a shard: it writes the full names, so it works in any program.
module PaymentShard
  class Client
    @[Logbuch::Annotations::Logged]
    @[Logbuch::Annotations::LogError(IO::Error, :warn)]
    def charge(@[Logbuch::Annotations::LogAs(:redacted)] card : String) : Nil
      raise IO::Error.new("offline")
    end
  end
end

# The program's own names.
module Logged
  def self.kind : String
    "the program's Logged"
  end
end

class LogError < Exception
end

class Shop
  @[Logbuch::Annotations::Logged]
  def place : Nil
    raise LogError.new("own exception")
  end
end

puts Logged.kind
begin
  PaymentShard::Client.new.charge("4111")
rescue IO::Error
end
begin
  Shop.new.place
rescue LogError
end
