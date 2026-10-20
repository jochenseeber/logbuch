require "../../../src/logbuch"

# Not opted in, so logged with inspect.
class Loose
end

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(items(:id))] loose : Loose) : Nil
  end
end

Offender.new.go(Loose.new)
