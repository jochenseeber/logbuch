require "../../../src/logbuch"

class Parent
  def inspect(io : IO) : Nil
    io << "parent"
  end
end

@[Logbuch::Annotations::LogType(inspect: :full)]
class Offender < Parent
  getter a = 1
end
