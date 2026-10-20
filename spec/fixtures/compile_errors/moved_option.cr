require "../../../src/logbuch"

class Offender
  include Logbuch::Annotations

  @[Logged(allow: KeyError)]
  def go : Int32
    1
  end
end

Offender.new.go
