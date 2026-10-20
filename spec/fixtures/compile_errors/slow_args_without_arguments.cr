require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(slow: {ms: 200, args: true})]
  def go : Int32
    1
  end
end

Offender.new.go
