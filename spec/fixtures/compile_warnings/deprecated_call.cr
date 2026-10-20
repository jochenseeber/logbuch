require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  @[Deprecated("use other")]
  def old : Int32
    1
  end
end

# The warning must point at this call.
Offender.new.old
