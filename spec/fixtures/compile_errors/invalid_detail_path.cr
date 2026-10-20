require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(Bogus::Full)]
  def go : Int32
    1
  end
end

Offender.new.go
