require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def initialize(@x : Int32 = 1)
  end
end

Offender.new
