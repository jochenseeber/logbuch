require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, cap: 5_000_000_000)]
  getter name : String = "n"
end

Logbuch.convert(Offender.new, detail: :full)
