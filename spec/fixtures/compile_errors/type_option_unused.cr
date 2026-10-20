require "../../../src/logbuch"

# Never converted, so only the build-time check sees the annotation.
@[Logbuch::Annotations::LogType(foo: 1)]
class Offender
  getter a = 1
end

Offender.new.a
