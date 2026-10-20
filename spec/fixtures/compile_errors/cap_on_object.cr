require "../../../src/logbuch"

# Not opted in, so logged with inspect.
class Loose
  getter numbers = [1, 2, 3]
end

class Offender
  include Logbuch::Annotations

  @[LogAs(:full, cap: 2)]
  getter loose : Loose = Loose.new
end

Logbuch.convert(Offender.new, detail: :full)
