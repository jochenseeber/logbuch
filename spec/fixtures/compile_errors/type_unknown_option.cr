require "../../../src/logbuch"

@[Logbuch::Annotations::LogType(locked: true)]
class Offender
  getter a = 1
end

Logbuch.convert(Offender.new, detail: :full)
