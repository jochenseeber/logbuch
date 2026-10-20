require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, length: 3)]
  getter count : Int32 = 1
end

Logbuch.convert(Offender.new, detail: :full)
