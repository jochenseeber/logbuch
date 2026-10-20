require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def build(&) : Nil
    with self yield
  end

  def add(value : Int32) : Nil
  end
end

Offender.new.build { add 1 }
