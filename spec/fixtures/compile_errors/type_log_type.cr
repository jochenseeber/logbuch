require "../../../src/logbuch"

@[Logbuch::Annotations::LogType(log: String)]
class Offender
  include Logbuch::Annotations

  @[Logged]
  def go : Int32
    1
  end
end

Offender.new.go
