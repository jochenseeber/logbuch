# build: --prelude=empty -Dlogbuch_timing=off
#
# A program with a prelude of its own, which lacks much of the standard
# prelude, such as `Array`'s methods, `Mutex` and `Set`. logbuch requires
# what it uses itself, so the program traces a method and converts values, and
# the types of the standard library that logbuch does not use stay undefined.
require "../../support/own_prelude"
require "../../../src/logbuch"

class PrintBackend < Log::Backend
  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    puts "#{entry.message} #{entry.data[:args]? || entry.data[:result]?}"
  end
end

Log.setup(:info, PrintBackend.new)

class Calculator
  include Logbuch::Annotations

  @[Logged(:info)]
  def add(left : Int32, right : Int32) : Int32
    left + right
  end
end

Calculator.new.add(1, 2)
puts "tuple: #{Logbuch.convert({1, "a"})}"
puts "hash: #{Logbuch.convert({"k" => 'c'})}"
puts "deque: #{Logbuch.convert(Deque{1, 2})}"
puts "path: #{Logbuch.convert(Path["/srv"], detail: :id)}"

# Checked once the whole program is read, after logbuch's own hooks.
macro finished
  puts "undefined: {{ %w[Complex Set SemanticVersion URI UUID].reject { |name| @top_level.has_constant?(name) }.join(" ").id }}"
end
