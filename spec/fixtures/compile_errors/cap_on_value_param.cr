require "../../../src/logbuch"
require "uuid"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(cap: 3)] id : UUID) : UUID
    id
  end
end

Offender.new.go(UUID.random)
