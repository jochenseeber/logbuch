require "../../../src/logbuch"

# No method of the type is traced, so logbuch does not trace the type.
class Offender
  def go(@[Logbuch::Annotations::Logged] name : String) : String
    name
  end
end

Offender.new.go("n")
