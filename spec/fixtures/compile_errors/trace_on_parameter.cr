require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[Logged] name : String) : String
    name
  end
end

Offender.new.go("n")
