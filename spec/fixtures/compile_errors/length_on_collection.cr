require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(length: 3)] tags : Array(String)) : Int32
    tags.size
  end
end

Offender.new.go(["a"])
