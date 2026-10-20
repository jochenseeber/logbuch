require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, cap: "many")]
  getter name : String = "n"
end

Logbuch.convert(Offender.new, detail: :full)
