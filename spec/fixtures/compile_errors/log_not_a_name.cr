require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(log: 42)]
  def go : Int32
    1
  end
end

Offender.new.go
