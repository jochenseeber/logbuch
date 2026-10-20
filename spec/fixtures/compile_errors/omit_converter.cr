require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:omit, converter: ->(value) { value.upcase })]
  getter name : String = "n"
end

Logbuch.convert(Offender.new, detail: :full)
