require "../../../src/logbuch"

# Never converted, so only the build-time check sees the annotation.
class Offender
  @[Logbuch::Annotations::LogAs(:bogus)]
  getter name = "n"
end

Offender.new.name
