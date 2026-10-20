# Messages: replace the converters that build the entry, exit and error
# messages from what is known about a traced method when the program compiles.
#
#   crystal run examples/messages.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

class Kitchen
  @[Logged("baking a cake")]
  def bake(flavor : String, @[LogAs(:redacted)] recipe : String) : String
    "#{flavor} cake"
  end

  @[Logged]
  def wash(*dishes : String) : Int32
    dishes.size
  end

  @[Logged("burning the toast", :debug)]
  def toast : Nil
    raise "smoke"
  end
end

# The converters are macros in Logbuch::Messages; reopen the module to replace
# them. Each gets `call`, a named tuple with the method's `type`, `method`,
# `class_method`, `label`, `description`, `level` and `params`, and expands to
# a String. This definition comes after the traced class and still applies,
# because the wrappers are generated once the whole program is read.
module Logbuch::Messages
  # "→ Kitchen#bake(flavor, recipe): baking a cake"
  macro entry_message(call)
    {% text = "→ #{call[:label].id}(#{call[:params].join(", ").id})" %}
    {% if call[:description] %}{% text += ": #{call[:description].id}" %}{% end %}
    {{ text }}
  end

  # "← Kitchen#bake"
  macro exit_message(call)
    {{ "← #{call[:label].id}" }}
  end

  # error_message is not replaced, so it keeps the default: "error " and the
  # description, or "!" and the label.
end

kitchen = Kitchen.new

puts "# Entry and exit messages from the replaced converters:"
kitchen.bake("lemon", "secret")
kitchen.wash("cup", "plate")

puts "\n# The error message keeps its default:"
begin
  kitchen.toast
rescue error
  puts "(caught #{error.message})"
end
