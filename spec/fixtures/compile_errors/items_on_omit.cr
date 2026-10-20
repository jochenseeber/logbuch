require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:omit, items(:id))]
  getter orders = ["a"]
end

Logbuch.convert(Offender.new)
