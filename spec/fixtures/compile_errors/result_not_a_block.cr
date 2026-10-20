require "../../../src/logbuch"

class Quiet
  include Logbuch::Annotations

  @[Logged(result: 3)]
  def run : Int32
    1
  end
end

Quiet.new.run
