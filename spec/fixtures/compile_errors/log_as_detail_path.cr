require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(Logbuch::Detail::Most)]
  getter name : String = "n"
end

Logbuch.convert(Offender.new, detail: :full)
