require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:summary, items(:id), items(:full))]
  getter orders = ["a"]
end

Logbuch.convert(Offender.new)
