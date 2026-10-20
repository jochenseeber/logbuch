require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(items(length: 3))] counts : Array(Int32)) : Nil
  end
end

Offender.new.go([1])
