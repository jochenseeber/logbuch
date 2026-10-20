require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(:redacted, converter: ->(card : String) { "****#{card[-4..]}" })] card : String) : Nil
  end
end

Offender.new.go("4111222233334444")
