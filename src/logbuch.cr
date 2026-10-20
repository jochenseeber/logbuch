require "./logbuch/annotations"
require "./logbuch/detail"
require "./logbuch/limits"
require "./logbuch/tracer"
require "./logbuch/fiber_state"
require "./logbuch/line_data"
require "./logbuch/locks"
require "./logbuch/values"
require "./logbuch/fields"
require "./logbuch/convert"
require "./logbuch/tracing"

# The build flags take a value: `-Dlogbuch=off` compiles tracing out, and
# `-Dlogbuch_timing=off` compiles timing out; `0` means `off` and `1` means
# `on`. Without a value, or without the flag, they are `on`.
{% unless [false, true, "on", "off", "1", "0"].includes?(flag?(:logbuch)) %}
  {% raise "logbuch: -Dlogbuch takes on, off, 1 or 0" %}
{% end %}
{% unless [false, true, "on", "off", "1", "0"].includes?(flag?(:logbuch_timing)) %}
  {% raise "logbuch: -Dlogbuch_timing takes on, off, 1 or 0" %}
{% end %}

# Method tracing for Crystal.
module Logbuch
  # The shard's version, which `shards version` reads from its `shard.yml`
  # when the program compiles.
  VERSION = {{ `shards version "#{__DIR__}/.."`.chomp.stringify }}
end
