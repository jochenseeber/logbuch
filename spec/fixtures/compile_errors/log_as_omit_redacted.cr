require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:omit, :redacted)]
  getter pin : String = "1"
end

Logbuch.convert(Offender.new, detail: :full)
