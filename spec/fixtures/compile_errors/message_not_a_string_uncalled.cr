require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  # Never called, so its wrapper is never typed.
  @[Logged]
  def go : Int32
    1
  end
end

module Logbuch::Messages
  macro exit_message(call)
    {{ call[:params].size }}
  end
end
