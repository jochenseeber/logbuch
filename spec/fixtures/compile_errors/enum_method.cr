require "../../../src/logbuch"

enum Color
  Red
  Green

  @[Logbuch::Annotations::Logged]
  def shout : String
    to_s.upcase
  end
end

Color::Red.shout
