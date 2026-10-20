# Annotation names without the top-level include: logbuch adds no names to a
# program by itself. A shard that uses logbuch, or a program with a `LogError`
# or `Logged` of its own, writes the annotations by their full names, gives
# them names of its own with an alias, or includes `Logbuch::Annotations`
# into the types that use them.
#
#   crystal run examples/full_names.cr

require "../src/logbuch"

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

# The program's own exception, which a top-level include of
# Logbuch::Annotations would clash with.
class LogError < Exception
end

# A name of the program's own for one annotation.
alias Traced = Logbuch::Annotations::Logged

module Vault
  class Safe
    # The full names work anywhere.
    @[Logbuch::Annotations::Logged("opening the safe")]
    @[Logbuch::Annotations::LogError(LogError, :warn, stacktrace: false)]
    def open(@[Logbuch::Annotations::LogAs(:redacted)] code : String) : Bool
      raise LogError.new("wrong code") unless code == "1234"
      true
    end

    # So does the alias.
    @[Traced("closing the safe")]
    def close : Nil
    end
  end

  # Included into a type, the module gives that type the short names.
  class Keyring
    include Logbuch::Annotations

    @[LogAs(:omit)]
    getter master_key = "k-123"
    getter owner = "Ada"

    @[Logged("adding a key")]
    def add(@[LogAs(:id)] key : String) : Int32
      1
    end
  end
end

safe = Vault::Safe.new

puts "# Full names, here with the program's own LogError among the exceptions:"
safe.open("1234")
begin
  safe.open("0000")
rescue error : LogError
  puts "(caught #{error.class})"
end

puts "\n# An alias:"
safe.close

puts "\n# Short names inside a type that includes Logbuch::Annotations:"
Vault::Keyring.new.add("k-7")

puts "\n# The include opts the type in, so its inspect leaves out the omitted key:"
puts Vault::Keyring.new.inspect
