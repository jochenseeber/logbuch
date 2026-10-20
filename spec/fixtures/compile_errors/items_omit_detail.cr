require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:summary, items(:omit))]
  getter orders = ["a"]
end

Logbuch.convert(Offender.new)
