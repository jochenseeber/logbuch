require "../../../src/logbuch"

@[Logbuch::Annotations::LogType(stacktrace: false)]
class Offender
  getter a = 1
end

Logbuch.convert(Offender.new, detail: :full)
