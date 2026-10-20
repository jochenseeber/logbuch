require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(length: 1)] letter : Char) : Char
    letter
  end
end

Offender.new.go('a')
