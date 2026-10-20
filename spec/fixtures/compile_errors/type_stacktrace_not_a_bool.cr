require "../../../src/logbuch"

@[Logbuch::Annotations::LogType(stacktrace: :no)]
class OffendingError < Exception
end

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go : Nil
    raise OffendingError.new
  end
end

Offender.new.go
