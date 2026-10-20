require "../../../src/logbuch"

@[Logbuch::Annotations::LogType(stacktrace: false, quiet: true)]
class OffendingError < Exception
end

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go : Nil
    raise OffendingError.new
  end
end

begin
  Offender.new.go
rescue OffendingError
end
