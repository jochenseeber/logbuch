require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[LogAs(:full)]
  def go : Int32
    1
  end
end

Offender.new.go
