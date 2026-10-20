require "../../../src/logbuch"

# Fails to compile exactly when tracing is on: the wrapper of a method with
# log: defines the constant that holds its log.
class Offender
  include Logbuch::Annotations

  @[Logged(log: "offender.go")]
  def go : Int32
    1
  end
end

# Expanded when it is typed, after the wrappers are generated.
def probe
  {% if Offender.has_constant?("LOGBUCH_LOG_0") %}
    {% raise "logbuch: tracing is on" %}
  {% end %}
end

probe
