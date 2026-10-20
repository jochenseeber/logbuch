require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:redacted)]
  def go : Int32
    1
  end
end

Offender.new.go
