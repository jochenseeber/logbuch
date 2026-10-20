require "../spec_helper"
require "../../src/logbuch"

# The converters are global, so a program that replaces them runs on its own:
# spec/fixtures/programs/messages.cr replaces the entry and exit converters after
# its traced types and prints each line's message.
describe MessageConverters do
  test "a converter defined after the traced types builds their messages from the call's facts" do
    output = run_program("messages", args: [] of String)
    lines = output.lines
    assert lines.includes?(%(Shop::Checkout|place|false|Shop::Checkout#place|"placing the order"|trace|order,coupon))
    assert lines.includes?(%(Shop::Checkout|build|true|Shop::Checkout.build|"building a checkout"|trace|))
    assert lines.includes?(%(Pallet|get|false|Pallet#get|nil|trace|value))
  end

  test "params lists internal names, splats by their bare names, and hidden parameters, but no unnamed splat or block" do
    output = run_program("messages", args: [] of String)
    lines = output.lines
    assert lines.includes?(%(Shop::Checkout|bulk|false|Shop::Checkout#bulk|nil|debug|first,rest,key,options))
    assert lines.includes?(%(Shop::Checkout|split|false|Shop::Checkout#split|nil|trace|a,b))
    assert lines.includes?(%(Shop::Checkout|each|false|Shop::Checkout#each|nil|trace|))
  end

  test "a computed message is built once, not on every call" do
    output = run_program("messages", args: [] of String)
    lines = output.lines
    assert lines.count("SHOP::CHECKOUT#PLACE") == 2
    assert lines.last == "exit builds: Pallet#get=1, Shop::Checkout#bulk=1, Shop::Checkout#each=1, " \
                         "Shop::Checkout#place=1, Shop::Checkout#split=1, Shop::Checkout.build=1"
  end

  test "a converter the program does not replace keeps its default" do
    output = run_program("messages", args: [] of String)
    assert output.lines.includes?("error failing")
  end

  test "a converter that expands to something other than a String fails to compile at the traced method" do
    assert compile_error("message_not_a_string").to_s.includes?("logbuch: the exit_message converter must expand to a String, not Int32, on Offender#go")
  end

  test "a converter cannot refer to the call's arguments" do
    assert compile_error("message_uses_argument").to_s.includes?("undefined local variable or method 'order'")
  end
end
