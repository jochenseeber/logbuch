require "../../../src/logbuch"

alias Missing = KeyError

class Offender
  include Logbuch::Annotations

  @[Logged]
  @[LogError(KeyError, stacktrace: false)]
  @[LogError(Missing, stacktrace: true)]
  def go : Int32
    1
  end
end

Offender.new.go
