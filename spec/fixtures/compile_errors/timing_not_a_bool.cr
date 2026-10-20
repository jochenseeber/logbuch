require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(timing: 1)]
  def go : Int32
    1
  end
end

Offender.new.go
