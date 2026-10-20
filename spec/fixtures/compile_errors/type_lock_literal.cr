require "../../../src/logbuch"

# Never converted nor inspected, so only the build-time check sees the
# annotation.
@[Logbuch::Annotations::LogType(lock: 42)]
class Offender
  getter a = 1
end

Offender.new.a
