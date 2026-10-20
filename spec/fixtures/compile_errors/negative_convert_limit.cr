require "../../../src/logbuch"

class Offender
  getter tags = ["a", "b"]

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    tracer.convert(@tags, cap: -1)
  end
end

Logbuch.convert(Offender.new)
