require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:redacted, length: 3)]
  getter token : String = "t"
end

Logbuch.convert(Offender.new, detail: :full)
