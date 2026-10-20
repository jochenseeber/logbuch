require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(slow: {ms: 200, args: :yes})]
  def go(count : Int32) : Int32
    1
  end
end

Offender.new.go(1)
