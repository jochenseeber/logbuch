require "../../../src/logbuch"

abstract class Offender
  include Logbuch::Annotations

  @[Logged]
  abstract def go : Int32
end

class Implementation < Offender
  def go : Int32
    1
  end
end

Implementation.new.go
