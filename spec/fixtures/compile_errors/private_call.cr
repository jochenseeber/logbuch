require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  private def secret : Int32
    1
  end
end

Offender.new.secret
