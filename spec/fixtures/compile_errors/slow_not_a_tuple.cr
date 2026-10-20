require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(slow: 200)]
  def go : Int32
    1
  end
end

Offender.new.go
