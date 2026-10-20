require "../../../src/logbuch"

# Never converted, so only the build-time check sees the annotation. `1e3`
# is a float, though it has no `.`.
class Offender
  @[Logbuch::Annotations::LogAs(length: 1e3)]
  getter name : String = "n"
end

Offender.new.name
