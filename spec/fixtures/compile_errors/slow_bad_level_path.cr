require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(slow: {ms: 200, level: ::Log::Severity::Loud})]
  def go : Int32
    1
  end
end

Offender.new.go
