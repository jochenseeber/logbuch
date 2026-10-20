require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  @[LogError(KeyError, stacktrace: :no)]
  def go : Int32
    1
  end
end

Offender.new.go
