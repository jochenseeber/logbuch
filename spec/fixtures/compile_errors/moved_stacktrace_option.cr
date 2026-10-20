require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(stacktrace: false)]
  def go : Int32
    1
  end
end

Offender.new.go
