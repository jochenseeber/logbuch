require "../../../src/logbuch"

NOT_A_LOG = "audit"

class Offender
  include Logbuch::Annotations

  @[Logged(log: NOT_A_LOG)]
  def go : Int32
    1
  end
end

Offender.new.go
