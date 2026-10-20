# build: --prelude=empty
#
# A program with a prelude of its own that requires `set` only after logbuch.
# `Set` still gets the `to_trace` that logs its items, not its `inspect` text.
require "../../support/own_prelude"
require "../../../src/logbuch"
require "set"

puts "set: #{Logbuch.convert(Set{1, 2})}"
