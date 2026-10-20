# Settings: the limits a conversion starts with, changed in code with
# `Logbuch.configure` and by whoever runs the program with the LOGBUCH_MAX_*
# environment variables, which the code can switch off. Built with
# -Dlogbuch=off, the settings are the defaults: it reads none of the variables,
# and `Logbuch.configure` only type-checks its block.
#
#   crystal run examples/settings.cr
#   LOGBUCH_MAX_CAP=4 crystal run examples/settings.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

# Stand-ins for variables set by whoever runs the program; set them in the
# shell to try other values. They are read once, when the settings are first
# used, so setting them later would change nothing.
ENV["LOGBUCH_MAX_DEPTH"] ||= "lots"
ENV["LOGBUCH_MAX_CAP"] ||= "3"
ENV["LOGBUCH_MAX_LENGTH"] ||= "20"

# A shelf with the shelf below it, for the depth limit.
@[LogType]
class Shelf
  @[LogAs(:id)]
  getter name : String
  getter below : Shelf?

  def initialize(@name : String, @below : Shelf? = nil)
  end
end

class Catalog
  @[Logged("listing the products")]
  def list(products : Array(String), note : String) : Int32
    products.size
  end

  @[Logged("stocking a shelf", :full)]
  def stock(shelf : Shelf) : Nil
  end
end

catalog = Catalog.new
products = ["apples", "bread", "cheese", "dates", "eggs"]
note = "deliver to the back door and ring twice"

puts "# The first use reads the variables. LOGBUCH_MAX_DEPTH is not a number, so"
puts "# it is ignored with a warning; the other two apply:"
puts Logbuch.settings
catalog.list(products, note)

puts "\n# A variable wins over the code, even when configure runs later:"
puts(Logbuch.configure do
  max_cap 2
  max_length 10
end)

puts "\n# env: false switches one setting's variable off, so the code's value applies:"
puts Logbuch.configure { max_cap 2, env: false }

puts "\n# use_env false switches every variable off:"
puts Logbuch.configure { use_env false }
catalog.list(products, note)

puts "\n# A value out of range raises ArgumentError and changes no setting. As a"
puts "# literal, such as max_depth 300, it fails the build instead:"
depth = 300
begin
  Logbuch.configure { max_depth depth }
rescue error : ArgumentError
  puts error.message
end
puts Logbuch.settings

puts "\n# max_depth sets how deep values nest; deeper objects are logged as their identity:"
shelves = Shelf.new("top", Shelf.new("middle", Shelf.new("bottom")))
catalog.stock(shelves)
puts Logbuch.configure { max_depth 2 }
catalog.stock(shelves)
