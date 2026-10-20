require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:summary, items(cap: 2))]
  getter names = {"a" => "ann"}
end

Logbuch.convert(Offender.new)
