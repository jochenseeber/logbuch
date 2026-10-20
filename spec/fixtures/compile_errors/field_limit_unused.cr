require "../../../src/logbuch"

# Never converted, so only the build-time check sees the annotation.
class Offender
  @[Logbuch::Annotations::LogAs(length: 3)]
  getter count : Int32 = 1
end

Offender.new.count
