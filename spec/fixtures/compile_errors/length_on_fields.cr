require "../../../src/logbuch"

@[Logbuch::Annotations::LogType]
struct FullName
  getter first = "Alexander"
end

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, length: 3)]
  getter name : FullName = FullName.new
end

Logbuch.convert(Offender.new, detail: :full)
