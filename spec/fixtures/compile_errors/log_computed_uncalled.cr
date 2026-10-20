require "../../../src/logbuch"

NOT_A_LOG = "audit".upcase

class Offender
  include Logbuch::Annotations

  # Never called, so its wrapper is never typed.
  @[Logged(log: NOT_A_LOG)]
  def go : Int32
    1
  end
end
