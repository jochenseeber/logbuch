require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def place(order : String) : String
    order
  end
end

# A message holds no values from the call, so naming a parameter fails.
module Logbuch::Messages
  macro entry_message(call)
    "placing #{{{ call[:params][0].id }}}"
  end
end

Offender.new.place("o-1")
