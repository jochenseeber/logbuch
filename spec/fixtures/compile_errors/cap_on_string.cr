require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(cap: 3)] name : String) : String
    name
  end
end

Offender.new.go("a")
