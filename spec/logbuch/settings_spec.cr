require "path"
require "uri"
require "wait_group"

require "../spec_helper"
require "../../src/logbuch"

module SettingsSpec
  # A list of nodes, each holding the next.
  @[Logbuch::Annotations::LogType]
  class Node
    getter next_node : Node?

    def initialize(@next_node : Node? = nil)
    end

    def self.chain(length : Int32) : Node
      node = new
      length.times { node = new(node) }
      node
    end
  end

  @[Logbuch::Annotations::LogType]
  class Limited
    include Logbuch::Annotations

    @[LogAs(:full, cap: 4)]
    getter capped : Array(Int32) = (1..10).to_a

    getter plain : Array(Int32) = (1..10).to_a
  end

  # Not opted in, so logged with inspect.
  class Loose
    @name = "loose"
  end

  # A struct logged by its fields.
  @[Logbuch::Annotations::LogType]
  struct Spot
    getter x = 1
    getter y = 2
  end

  # Holds a struct next to an object.
  @[Logbuch::Annotations::LogType]
  class Corner
    getter spot = Spot.new
    getter node = Node.new
  end

  # Changes the settings while it is being converted.
  class Reconfigures
    def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
      Logbuch.configure { max_cap 1 }
      tracer.convert([1, 2, 3])
    end
  end
end

# Sets every setting back to its default and switches the variables on again,
# for the tests that change them; the spec process has no LOGBUCH_ variables.
def restore_settings : Nil
  Logbuch.configure do
    use_env true
    max_depth Logbuch::MAX_DEPTH, env: true
    max_cap Logbuch::MAX_CAP, env: true
    max_length Logbuch::MAX_LENGTH, env: true
  end
end

# The settings as a tuple, for comparing them in one assertion.
def current_settings : {UInt32, UInt32, UInt32}
  settings = Logbuch.settings
  {settings.max_depth, settings.max_cap, settings.max_length}
end

# The nesting depth of a converted `SettingsSpec::Node` chain.
def node_depth(value : Log::Metadata::Value) : Int32
  depth = 0
  while (hash = value.as_h?) && (inner = hash["next_node"]?)
    depth += 1
    value = inner
  end
  depth
end

describe Settings do
  after { restore_settings }

  test "the settings start at the built-in defaults" do
    assert current_settings == {Logbuch::MAX_DEPTH, Logbuch::MAX_CAP, Logbuch::MAX_LENGTH}
    assert Logbuch.settings.inspect == "#<Logbuch::Settings max_depth: 16, max_cap: 100, max_length: 1024>"
  end

  test "configure sets the settings its block names and returns the settings in effect" do
    settings = Logbuch.configure do
      max_depth 3
      max_cap 50
    end
    assert({settings.max_depth, settings.max_cap, settings.max_length} == {3_u32, 50_u32, Logbuch::MAX_LENGTH})
    assert current_settings == {3_u32, 50_u32, Logbuch::MAX_LENGTH}
  end

  test "each configure starts from the current settings" do
    Logbuch.configure { max_cap 5 }
    Logbuch.configure { max_length 7 }
    assert current_settings == {Logbuch::MAX_DEPTH, 5_u32, 7_u32}
  end

  test "the largest values are accepted" do
    Logbuch.configure do
      max_depth Logbuch::DEPTH_CEILING
      max_cap UInt32::MAX
      max_length UInt32::MAX
    end
    assert current_settings == {Logbuch::DEPTH_CEILING, UInt32::MAX, UInt32::MAX}
  end

  test "the largest values are accepted as literals" do
    Logbuch.configure do
      max_depth 256
      max_cap 4_294_967_295
      max_length 0
    end
    assert current_settings == {Logbuch::DEPTH_CEILING, UInt32::MAX, 0_u32}
  end

  test "a value out of range raises and changes no setting" do
    # A literal out of range fails the build, so the values are variables.
    depth = 257
    message = begin
      Logbuch.configure do
        max_cap 5
        max_depth depth
      end
      nil
    rescue error : ArgumentError
      error.message
    end
    assert message == "logbuch: max_depth takes 0 to 256, not 257"
    assert current_settings == {Logbuch::MAX_DEPTH, Logbuch::MAX_CAP, Logbuch::MAX_LENGTH}
  end

  test "the setters take any integer type" do
    depth = 3
    items = 50_i64
    length = 7_u8
    Logbuch.configure do
      max_depth depth
      max_cap items
      max_length length
    end
    assert current_settings == {3_u32, 50_u32, 7_u32}
  end

  test "a negative value or one above UInt32 raises and changes no setting" do
    negative = -1
    large = 5_000_000_000_i64
    messages = [
      -> { Logbuch.configure { max_cap negative } },
      -> { Logbuch.configure { max_length large } },
    ].map do |configure|
      configure.call
      nil
    rescue error : ArgumentError
      error.message
    end
    assert messages == ["logbuch: max_cap takes 0 to 4294967295, not -1",
                        "logbuch: max_length takes 0 to 4294967295, not 5000000000"]
    assert current_settings == {Logbuch::MAX_DEPTH, Logbuch::MAX_CAP, Logbuch::MAX_LENGTH}
  end

  test "a literal out of range fails the build" do
    assert compile_error("configure_literal_above_maximum").to_s.includes?("logbuch: max_depth takes 0 to 256, not 300")
    assert compile_error("configure_negative_literal").to_s.includes?("logbuch: max_cap takes 0 to 4294967295, not -1")
  end

  test "a block that does not compile, or none, fails the build" do
    assert compile_error("configure_unknown_setting").to_s.includes?("undefined method 'max_dept' for Logbuch::Configuration")
    assert compile_error("configure_without_block").to_s.includes?("logbuch: Logbuch.configure takes a block, such as Logbuch.configure { max_depth 3 }")
  end

  test "a block that raises changes no setting" do
    assert_raises(KeyError) do
      Logbuch.configure do
        max_cap 5
        raise KeyError.new("oops")
      end
    end
    assert current_settings == {Logbuch::MAX_DEPTH, Logbuch::MAX_CAP, Logbuch::MAX_LENGTH}
  end

  test "switching the variables off keeps the values set in code" do
    Logbuch.configure do
      max_cap 5, env: false
      use_env false
      max_length 6
    end
    assert current_settings == {Logbuch::MAX_DEPTH, 5_u32, 6_u32}
  end

  test "a conversion starts with the item and length settings" do
    Logbuch.configure do
      max_cap 3
      max_length 5
    end
    assert Logbuch.convert((1..10).to_a, detail: :full).as_a.map(&.to_s) == ["1", "2", "3", "… 7 more"]
    assert Logbuch.convert("abcdefgh").as_s == "abcde… (+3 bytes)"
    assert pair_keys(Logbuch.convert({"abcdefgh" => 1}, detail: :full)) == ["abcde… (+3 bytes)"]
    assert Logbuch.convert(SettingsSpec::Loose.new, detail: :full).as_s == "#<Set…"
    assert Logbuch.convert(ArgumentError.new("abcdefgh")).as_h["message"].as_s == "abcde… (+3 bytes)"
  end

  test "a conversion starts with the depth setting" do
    Logbuch.configure { max_depth 2 }
    head = SettingsSpec::Node.chain(10)
    value = Logbuch.convert(head, detail: :full)
    assert node_depth(value) == 2
    cut = head.next_node.try(&.next_node) || raise SampleError.new("the chain ends early")
    assert value.to_s.includes?("#<SettingsSpec::Node:0x#{cut.object_id.to_s(16)}>")
  end

  test "a depth of 0 logs the traced object as its identity" do
    Logbuch.configure { max_depth 0 }
    node = SettingsSpec::Node.new
    assert Logbuch.convert(node).as_s == "#<SettingsSpec::Node:0x#{node.object_id.to_s(16)}>"
  end

  test "a depth of 0 logs a struct as its identity" do
    Logbuch.configure { max_depth 0 }
    spot = SettingsSpec::Spot.new
    assert Logbuch.convert(spot, detail: :full).as_s == "#<SettingsSpec::Spot>"
    assert Logbuch.convert(spot, detail: :full).as_s == Logbuch.convert(spot, detail: :id).as_s
    assert Logbuch.convert({1, 2}).as_s == "#<Tuple>"
    assert Logbuch.convert({a: 1}).as_s == "#<NamedTuple>"
    assert Logbuch.convert(Time.utc(2026, 1, 2)).as_time == Time.utc(2026, 1, 2)
  end

  test "a depth of 0 logs a stdlib value type by value, also one that is a class" do
    Logbuch.configure { max_depth 0 }
    assert Logbuch.convert(URI.parse("https://example.com/a"), detail: :full).as_s == "https://example.com/a"
    assert Logbuch.convert(Time::Location.fixed("CET", 3600), detail: :full).as_s == "CET"
    assert Logbuch.convert(Path["/srv"], detail: :full).as_s == "/srv"
  end

  test "at the depth limit a struct is cut like the object beside it" do
    Logbuch.configure { max_depth 1 }
    corner = SettingsSpec::Corner.new
    value = Logbuch.convert(corner, detail: :full).as_h
    assert value["node"].as_s == "#<SettingsSpec::Node:0x#{corner.node.object_id.to_s(16)}>"
    assert value["spot"].as_s == Logbuch.convert(corner.spot, detail: :id).as_s
  end

  test "an annotation's limits still apply to its value" do
    Logbuch.configure do
      max_depth 2
      max_cap 2
    end
    value = Logbuch.convert(SettingsSpec::Limited.new, detail: :full).as_h
    assert value["capped"].as_a.size == 5
    assert value["capped"].as_a.last.as_s == "… 6 more"
    assert value["plain"].as_a.size == 3
    assert value["plain"].as_a.last.as_s == "… 8 more"
  end

  test "a conversion finishes with the settings it started with" do
    value = Logbuch.convert(SettingsSpec::Reconfigures.new, detail: :full)
    assert value.as_a.map(&.as_i) == [1, 2, 3]
    assert Logbuch.convert([1, 2, 3], detail: :full).as_a.map(&.to_s) == ["1", "… 2 more"]
  end

  test "a conversion in another thread never sees a mix of old and new settings" do
    threads = Fiber::ExecutionContext::Parallel.new("settings", 4)
    mixed = Atomic(Int32).new(0)
    converted = Atomic(Int32).new(0)
    running = Atomic(Bool).new(true)
    group = WaitGroup.new
    Logbuch.configure do
      max_cap 2
      max_length 2
    end
    4.times do
      group.add
      threads.spawn do
        while running.get
          value = Logbuch.convert({(1..10).to_a, "abcdefghij"}, detail: :full).as_a
          # The item and length limits are always equal, so the items shown
          # match the characters kept.
          items = value[0].as_a.size - 1
          mixed.add(1) unless value[1].as_s.index('…') == items
          converted.add(1)
        end
      ensure
        group.done
      end
    end
    2000.times do |index|
      size = index.even? ? 2_u32 : 3_u32
      Logbuch.configure do
        max_cap size
        max_length size
      end
      Fiber.yield
    end
    running.set(false)
    group.wait
    assert converted.get > 0
    assert mixed.get == 0
  end
end

# The line `show` prints for these settings.
def shown(depth : Int, items : Int, length : Int) : String
  "max_depth: #{depth}, max_cap: #{items}, max_length: #{length}\n"
end

# The warning for *variable* holding *value*, which takes 0 to *maximum*.
def bad_variable(variable : String, value : String, maximum : Int) : String
  "WARN logbuch: ignoring #{variable}=#{value.inspect}: it takes a decimal integer from 0 to #{maximum}\n"
end

describe SettingsFromEnvironment do
  test "a valid variable wins over the code and the default, also when configure runs later" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "3", "LOGBUCH_MAX_CAP" => "007"},
      args: ["show", "configure:max_depth=5", "configure:max_cap=6", "configure:max_length=60", "show"])
    assert output == shown(3, 7, 1024) + shown(3, 7, 60)
  end

  test "the largest and smallest values are accepted" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "256", "LOGBUCH_MAX_CAP" => "4294967295", "LOGBUCH_MAX_LENGTH" => "0"},
      args: ["show"])
    assert output == shown(256, 4294967295, 0)
  end

  test "a bad value is ignored, with one warning naming the variable and its value" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "257", "LOGBUCH_MAX_CAP" => "abc", "LOGBUCH_MAX_LENGTH" => "4294967296"},
      args: ["show", "configure:max_cap=6", "show"])
    assert output == bad_variable("LOGBUCH_MAX_DEPTH", "257", 256) +
                     bad_variable("LOGBUCH_MAX_CAP", "abc", 4294967295) +
                     bad_variable("LOGBUCH_MAX_LENGTH", "4294967296", 4294967295) +
                     shown(16, 100, 1024) + shown(16, 6, 1024)
  end

  test "only plain decimal digits are a valid value" do
    [{"-1", "+5", ""}, {" 5", "5 ", "1_0"}, {"0x10", "1e3", "٣"}].each do |depth, items, length|
      output = run_program("settings",
        env: {"LOGBUCH_MAX_DEPTH" => depth, "LOGBUCH_MAX_CAP" => items, "LOGBUCH_MAX_LENGTH" => length},
        args: ["show"])
      assert output == bad_variable("LOGBUCH_MAX_DEPTH", depth, 256) +
                       bad_variable("LOGBUCH_MAX_CAP", items, 4294967295) +
                       bad_variable("LOGBUCH_MAX_LENGTH", length, 4294967295) +
                       shown(16, 100, 1024)
    end
  end

  test "a log backend that raises loses the warning, not the settings" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "abc", "LOGBUCH_MAX_CAP" => "7"},
      args: ["failing_log", "show"])
    assert output == shown(16, 7, 1024)
  end

  test "use_env false ignores every variable and never checks one" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "3", "LOGBUCH_MAX_CAP" => "abc"},
      args: ["configure:use_env=false", "show"])
    assert output == shown(16, 100, 1024)
  end

  test "env: false ignores one setting's variable and never checks it" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "3", "LOGBUCH_MAX_CAP" => "abc", "LOGBUCH_MAX_LENGTH" => "50"},
      args: ["configure:max_cap=5,env=false", "configure:max_length=256,env=false", "show"])
    assert output == shown(3, 5, 256)
  end

  test "switching the variables off drops the values applied from them" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "3"},
      args: ["show", "configure:use_env=false", "show", "configure:use_env=true", "show"])
    assert output == shown(3, 100, 1024) + shown(16, 100, 1024) + shown(3, 100, 1024)
  end

  test "env: false lasts until env: true, also when the setting is set again" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "3"},
      args: ["configure:max_depth=5,env=false", "show", "configure:max_depth=6", "show",
             "configure:max_depth=6,env=true", "show"])
    assert output == shown(5, 100, 1024) + shown(6, 100, 1024) + shown(3, 100, 1024)
  end

  test "a bad variable switched on later is checked then, and warns once" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_CAP" => "abc"},
      args: ["configure:use_env=false", "show", "configure:use_env=true", "show", "configure:max_cap=5", "show"])
    assert output == shown(16, 100, 1024) + bad_variable("LOGBUCH_MAX_CAP", "abc", 4294967295) +
                     shown(16, 100, 1024) + shown(16, 5, 1024)
  end

  test "the variables are read once, when the settings are first used" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "3"},
      args: ["show", "set:LOGBUCH_MAX_DEPTH=4", "set:LOGBUCH_MAX_CAP=5", "configure:max_length=7", "show"])
    assert output == shown(3, 100, 1024) + shown(3, 100, 7)
  end

  test "the variables are read once, when configure runs first" do
    output = run_program("settings",
      env: {"LOGBUCH_MAX_DEPTH" => "3"},
      args: ["configure:max_length=7", "set:LOGBUCH_MAX_DEPTH=4", "show"])
    assert output == shown(3, 100, 7)
  end
end
