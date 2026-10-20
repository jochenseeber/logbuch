require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, converter: ->(a, _b) { a })]
  getter name : String = "n"
end

Logbuch.convert(Offender.new, detail: :full)
