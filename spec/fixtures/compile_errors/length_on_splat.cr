require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(length: 3)] *names : String) : Int32
    names.size
  end
end

Offender.new.go("a")
