require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:summary, :redacted, converter: ->(pin : String) { pin.size })]
  getter pin = "1234"
end

Logbuch.convert(Offender.new)
