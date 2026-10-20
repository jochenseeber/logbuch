require "../../../src/logbuch"

@[Logbuch::Annotations::LogType(stacktrace: false)]
class Offender
  include Logbuch::Annotations

  @[Logged]
  def go : Int32
    1
  end
end

Offender.new.go
