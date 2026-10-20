# The basics: trace methods with `@[Logged]`, describe them, and see the entry,
# exit and error lines a call writes.
#
#   crystal run examples/basic.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

class Calculator
  # Without a description, the messages are the method name.
  @[Logged]
  def add(a : Int32, b : Int32) : Int32
    a + b
  end

  # With a description, the messages read "dividing two numbers",
  # "done dividing two numbers" and "error dividing two numbers";
  # examples/messages.cr shows how to build them differently.
  @[Logged("dividing two numbers")]
  def divide(a : Int32, b : Int32) : Int32
    return 0 if a == 0 # a plain return still writes the exit line
    a // b
  end

  # A missing name is an expected outcome: KeyError is logged as the result.
  @[Logged("looking up a constant")]
  @[LogAccept(KeyError)]
  def constant(name : String) : Float64
    {"pi" => 3.14159, "e" => 2.71828}[name]
  end

  # A method returning Nil logs no result.
  @[Logged("clearing the memory")]
  def clear : Nil
  end
end

calculator = Calculator.new

puts "# A traced call writes an entry and an exit line:"
calculator.add(1, 2)

puts "\n# A description becomes the message, and return works as usual:"
calculator.divide(0, 5)
calculator.divide(10, 2)

puts "\n# An exception writes an error line and is raised again unchanged:"
begin
  calculator.divide(1, 0)
rescue error : DivisionByZeroError
  puts "(caught #{error.class})"
end

puts "\n# An accepted exception is logged as the result and raised again:"
begin
  calculator.constant("tau")
rescue error : KeyError
  puts "(caught #{error.class})"
end

puts "\n# A Nil method has no result:"
calculator.clear
