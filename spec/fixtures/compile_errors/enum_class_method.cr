require "../../../src/logbuch"

module Palette
  enum Shade
    Light
    Dark

    @[Logbuch::Annotations::Logged]
    def self.pick(name : String) : Shade
      parse(name)
    end
  end
end

Palette::Shade.pick("dark")
