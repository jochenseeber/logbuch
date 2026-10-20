require "../../../src/logbuch"

# Never converted, so only the build-time check sees the annotation.
class Offender
  def initialize(@[Logbuch::Annotations::LogAs(length: 3)] @count : Int32 = 1)
  end
end

Offender.new
