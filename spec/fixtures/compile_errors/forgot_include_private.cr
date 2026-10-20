require "../../../src/logbuch"

private class Forgetful
  @[Logbuch::Annotations::Logged]
  def go : Int32
    1
  end
end

Forgetful.new.go
