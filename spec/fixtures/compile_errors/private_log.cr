require "../../../src/logbuch"

class Offender
  include Logbuch::Tracing
end

Offender::LOGBUCH_LOG
