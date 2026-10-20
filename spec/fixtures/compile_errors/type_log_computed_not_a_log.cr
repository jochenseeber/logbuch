require "../../../src/logbuch"

NOT_A_LOG = "audit".upcase

@[Logbuch::Annotations::LogType(log: NOT_A_LOG)]
class Offender
  include Logbuch::Annotations

  @[Logged]
  def go : Int32
    1
  end
end

Offender.new.go
