require "../../../src/logbuch"

class Quiet
  include Logbuch::Annotations

  @[Logged(:omit, result: ->(value) { value })]
  def run : Int32
    1
  end
end

Quiet.new.run
