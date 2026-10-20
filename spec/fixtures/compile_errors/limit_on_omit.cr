require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:omit, cap: 3)]
  getter tags : Array(String) = ["a"]
end

Logbuch.convert(Offender.new, detail: :full)
