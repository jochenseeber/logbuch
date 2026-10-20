require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:summary, items(length: "long"))]
  getter names = ["ann"]
end

Logbuch.convert(Offender.new)
