require "../../../src/logbuch"

# No method of the type is traced, so logbuch does not trace the type.
class Offender
  @[Logbuch::Annotations::LogAs(:full)]
  def go : Int32
    1
  end
end

Offender.new.go
