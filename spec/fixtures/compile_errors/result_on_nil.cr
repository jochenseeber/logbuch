require "../../../src/logbuch"

class Quiet
  include Logbuch::Annotations

  @[Logged(result: ->(value) { value })]
  def run : Nil
  end
end

Quiet.new.run
