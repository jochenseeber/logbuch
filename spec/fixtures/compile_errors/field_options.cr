require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, timing: false)]
  getter name : String = "n"
end

Logbuch.convert(Offender.new, detail: :full)
