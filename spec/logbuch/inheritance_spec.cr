require "../spec_helper"
require "../../src/logbuch"

module Honks
  include Logbuch::Annotations

  @[Logged]
  def honk : String
    "honk"
  end
end

class Vehicle
  include Logbuch::Annotations

  @[Logged]
  def start : String
    "vehicle"
  end

  @[Logged]
  def drive(other : Vehicle?) : String
    "vehicle"
  end

  @[Logged]
  def stall : Nil
    raise ArgumentError.new("stalled")
  end

  @[Logged]
  def each_wheel(&) : Nil
    4.times { |wheel| yield wheel }
  end

  @[Logged]
  def countdown(count : Int32) : Int32
    count == 0 ? 0 : countdown(count - 1)
  end

  @[Logged]
  def self.build : String
    "vehicle"
  end
end

class Car < Vehicle
  include Logbuch::Annotations

  include Honks

  @[Logged]
  def start : String
    "car with #{super}"
  end

  @[Logged]
  def drive(other : Vehicle?) : String
    other.try &.drive(nil)
    super
  end

  @[Logged]
  def stall : Nil
    super
  end

  @[Logged]
  def each_wheel(&) : Nil
    super { |wheel| yield wheel }
  end

  @[Logged]
  def honk : String
    super.upcase
  end

  @[Logged]
  def self.build : String
    "car with #{super}"
  end
end

class SportsCar < Car
  include Logbuch::Annotations

  @[Logged]
  def start : String
    "sports #{super}"
  end
end

class Truck < Vehicle
  def start : String
    "truck with #{super}"
  end
end

class Archive
  include Logbuch::Annotations

  @[Logged]
  def save(id : Int32) : String
    "saved #{id}"
  end
end

# Calls the overload of its own name that its parent class defines.
class Ledger < Archive
  include Logbuch::Annotations

  @[Logged]
  def save(name : String) : String
    save(name.size)
  end
end

# Calls an overload of its own name in the same class.
class Shelf
  include Logbuch::Annotations

  @[Logged]
  def put(count : Int32) : Int32
    count
  end

  @[Logged]
  def put(name : String) : Int32
    put(name.size)
  end
end

module Shape
  include Logbuch::Annotations

  @[Logged]
  def area : Int32
    2
  end
end

# Calls the overload of its own name that an included module defines, on
# another square, on itself, and from a proc, which holds a copy of it.
struct Square
  include Logbuch::Annotations
  include Shape

  def initialize(@side : Int32)
  end

  @[Logged]
  def area(scale : Int32) : Int32
    Square.new(@side + 1).area * scale
  end

  @[Logged]
  def area(name : String) : Int32
    area * name.size
  end

  @[Logged]
  def area(scale : Float64) : Int32
    -> { area }.call
  end
end

# A struct without instance variables, so all of its instances are one
# receiver.
struct Speck
  include Logbuch::Annotations
  include Shape

  @[Logged]
  def area(scale : Int32) : Int32
    Speck.new.area * scale
  end
end

# Its square is stored where the frame starts, at the same address.
struct Framed
  include Logbuch::Annotations
  include Shape

  def initialize(@square : Square, @margin : Int32 = 0)
  end

  @[Logged]
  def area(scale : Int32) : Int32
    @square.area * scale
  end
end

class Drawing
  def initialize(@square : Square)
  end

  def draw : Int32
    @square.area(3)
  end
end

abstract struct Tool
  include Logbuch::Annotations

  @[Logged]
  def use : String
    "tool"
  end
end

struct Hammer < Tool
  def initialize(@weight : Int32)
  end

  @[Logged]
  def use : String
    "hammer with #{super}"
  end
end

# Calls super from a proc, which holds a copy of the wrench.
struct Wrench < Tool
  def initialize(@size : Int32)
  end

  @[Logged]
  def use : String
    -> { "wrench with #{super}" }.call
  end
end

describe SuperCalls do
  test "the same method on another struct is logged" do
    entries = capture_log { assert Square.new(1).area(3) == 6 }
    assert entries.map(&.message) == [">Square#area", ">Shape#area", "<Shape#area", "<Square#area"]
  end

  test "the same method on another struct is logged wherever the struct is stored" do
    square = Square.new(1)
    squares = [Square.new(1), Square.new(2)]
    entries = capture_log do
      square.area(3)
      squares[1].area(3)
      Drawing.new(square).draw
    end
    assert entries.map(&.message) == [">Square#area", ">Shape#area", "<Shape#area", "<Square#area"] * 3
  end

  test "the same method on a struct stored at the start of another is logged" do
    entries = capture_log { assert Framed.new(Square.new(1)).area(3) == 6 }
    assert entries.map(&.message) == [">Framed#area", ">Shape#area", "<Shape#area", "<Framed#area"]
  end

  test "an overload of the same name that an included module defines counts as a super call on a struct" do
    entries = capture_log { assert Square.new(1).area("abc") == 6 }
    assert entries.map(&.message) == [">Square#area", "<Square#area"]
  end

  test "a traced struct override that calls a traced super logs one call" do
    entries = capture_log { assert Hammer.new(1).use == "hammer with tool" }
    assert entries.map(&.message) == [">Hammer#use", "<Hammer#use"]
  end

  test "a struct method called from a proc is called on a copy and logged" do
    entries = capture_log do
      assert Square.new(1).area(1.5) == 2
      assert Wrench.new(1).use == "wrench with tool"
    end
    assert entries.map(&.message) == [
      ">Square#area", ">Shape#area", "<Shape#area", "<Square#area",
      ">Wrench#use", ">Tool#use", "<Tool#use", "<Wrench#use",
    ]
  end

  test "all instances of a struct without instance variables are one receiver" do
    entries = capture_log { assert Speck.new.area(3) == 6 }
    assert entries.map(&.message) == [">Speck#area", "<Speck#area"]
  end

  test "a traced override that calls a traced super logs one call" do
    entries = capture_log { assert Car.new.start == "car with vehicle" }
    assert entries.size == 2
    assert entries.all? { |entry| entry.data[:method].as_s == "Car#start" }
    assert entries[1].data[:result].as_s == "car with vehicle"
  end

  test "a chain of traced supers logs only the outermost call" do
    entries = capture_log { assert SportsCar.new.start == "sports car with vehicle" }
    assert entries.size == 2
    assert entries.all? { |entry| entry.data[:method].as_s == "SportsCar#start" }
  end

  test "an untraced override logs the traced super it calls" do
    entries = capture_log { Truck.new.start }
    assert entries.size == 2
    assert entries.all? { |entry| entry.data[:method].as_s == "Vehicle#start" }
  end

  test "the same method on another object is logged" do
    entries = capture_log { Car.new.drive(Vehicle.new) }
    assert entries.map(&.data[:method].as_s) == ["Car#drive", "Vehicle#drive", "Vehicle#drive", "Car#drive"]
  end

  test "recursion logs every call" do
    assert capture_log { Car.new.countdown(2) }.size == 6
  end

  test "an exception from a traced super logs one error line" do
    entries = capture_log { Car.new.stall rescue nil }
    assert entries.size == 2
    assert entries[1].message == "!Car#stall"
  end

  test "an exception from a traced super logs one error line when both levels are disabled" do
    logs = [::Log.for("car"), ::Log.for("vehicle")]
    logs.each(&.level=(:info))
    entries = capture_log { Car.new.stall rescue nil }
    assert entries.size == 1
    assert entries[0].severity.error?
    assert entries[0].data[:error].as_h["message"].as_s == "stalled"
  ensure
    logs.try &.each(&.level=(:trace))
  end

  test "a traced super stays silent when the override's level is disabled" do
    log = ::Log.for("car")
    log.level = :info
    entries = capture_log { assert Car.new.start == "car with vehicle" }
    assert entries.empty?
  ensure
    ::Log.for("car").level = :trace
  end

  test "an overload of the same name that a parent class defines counts as a super call" do
    entries = capture_log { assert Ledger.new.save("four") == "saved 4" }
    assert entries.map(&.message) == [">Ledger#save", "<Ledger#save"]
    assert entries[0].data[:args].as_h["name"].as_s == "four"
  end

  test "an overload of the same name in the same class is logged" do
    entries = capture_log { assert Shelf.new.put("four") == 4 }
    assert entries.map(&.message) == [">Shelf#put", ">Shelf#put", "<Shelf#put", "<Shelf#put"]
    assert entries[0].data[:args].as_h["name"].as_s == "four"
    assert entries[1].data[:args].as_h["count"].as_i == 4
  end

  test "a yielding override that calls super logs one call" do
    wheels = [] of Int32
    entries = capture_log { Car.new.each_wheel { |wheel| wheels << wheel } }
    assert wheels == [0, 1, 2, 3]
    assert entries.size == 2
  end

  test "a traced override of a traced module method logs one call" do
    entries = capture_log { assert Car.new.honk == "HONK" }
    assert entries.size == 2
    assert entries[0].data[:method].as_s == "Car#honk"
  end

  test "a traced class method that calls super logs one call" do
    entries = capture_log { assert Car.build == "car with vehicle" }
    assert entries.size == 2
    assert entries[0].data[:method].as_s == "Car.build"
  end
end
