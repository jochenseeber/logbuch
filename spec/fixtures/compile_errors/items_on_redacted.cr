require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(:redacted, items(:id))] orders : Array(String)) : Nil
  end
end

Offender.new.go(["a"])
