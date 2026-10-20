require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  @[LogAccept(KeyError)]
  @[LogError(KeyError, stacktrace: false)]
  def go : Int32
    1
  end
end

Offender.new.go
