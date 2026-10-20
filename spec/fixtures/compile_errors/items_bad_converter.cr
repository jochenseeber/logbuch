require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(items(converter: 3))] orders : Array(String)) : Nil
  end
end

Offender.new.go(["a"])
