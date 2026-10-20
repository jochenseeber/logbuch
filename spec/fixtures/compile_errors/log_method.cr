require "../../../src/logbuch"

class Offender
  include Logbuch::Tracing
end

Offender.__logbuch_log
