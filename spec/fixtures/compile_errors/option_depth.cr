require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, depth: 2)]
  getter orders = ["a"]
end

Logbuch.convert(Offender.new)
