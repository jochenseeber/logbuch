require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(log: String)]
  def go : Int32
    1
  end
end

Offender.new.go
