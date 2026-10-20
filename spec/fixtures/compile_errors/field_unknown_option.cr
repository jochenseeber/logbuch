require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, color: :red)]
  getter name : String = "n"
end

Logbuch.convert(Offender.new, detail: :full)
