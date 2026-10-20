require "../../../src/logbuch"

private module Workshop
  class Bench
    @[Logbuch::Annotations::Logged]
    def go : Int32
      1
    end
  end
end

Workshop::Bench.new.go
