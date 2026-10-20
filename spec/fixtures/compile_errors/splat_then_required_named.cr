require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(first : Int32, *rest : Int32, key : String) : Int32
    first
  end
end

Offender.new.go(1, 2, key: "k")
