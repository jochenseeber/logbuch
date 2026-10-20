require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:summary, items(:id))]
  getter name = "ann"
end

Logbuch.convert(Offender.new)
