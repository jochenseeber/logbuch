require "../spec_helper"
require "../../src/logbuch"

{% if %w[off 0].includes?(flag?(:logbuch)) %}
  class Untraced
    include Logbuch::Annotations

    @[Logged(:full, timing: true)]
    @[LogError(KeyError, stacktrace: false)]
    def go(x : Int32) : Int32
      x + 1
    end
  end

  @[Logbuch::Annotations::LogType]
  class Labeled
    include Logbuch::Annotations

    @[LogAs(:id)]
    getter label : String

    def initialize(@label : String)
    end
  end

  # Not opted in, so its identity is its `inspect` text.
  class Noted
    getter text = "x" * 2000
  end

  describe TracingOff do
    test "traced methods run but log nothing" do
      entries = capture_log { assert Untraced.new.go(1) == 2 }
      assert entries.empty?
    end

    test "configure only type-checks its block, which does not run, and returns the defaults" do
      ran = false
      settings = Logbuch.configure do
        ran = true
        max_cap 5
      end
      assert !ran
      assert settings.max_cap == Logbuch::MAX_CAP
      assert Logbuch.settings.inspect == "#<Logbuch::Settings max_depth: 16, max_cap: 100, max_length: 1024>"
    end

    test "configure does not check a value out of range that is not a literal" do
      # Above `DEPTH_CEILING`, which raises with tracing on.
      depth = 300
      settings = Logbuch.configure { max_depth depth }
      assert settings.max_depth == Logbuch::MAX_DEPTH
      assert Logbuch.settings.max_depth == Logbuch::MAX_DEPTH
    end

    test "the settings are the defaults: no variable is read or warned about, and configure changes nothing" do
      output = run_program("settings", flags: ["logbuch=off"],
        env: {"LOGBUCH_MAX_DEPTH" => "lots", "LOGBUCH_MAX_CAP" => "3"},
        args: ["show", "configure:max_length=60", "show", "configure:use_env=true", "show"])
      assert output == "max_depth: 16, max_cap: 100, max_length: 1024\n" * 3
    end

    test "inspect and to_s text is cut as with tracing on, though written in full first" do
      assert Logbuch.__inspect(["ä" * 2000], 10) == %q([") + "ä" * 8 + "…"
      assert Logbuch.__inspect("abc", 5) == %q("abc")
      assert Logbuch.__text([1, 2, 3], 6) == "[1, 2,…"
      assert Logbuch.__text("abcdef", 6) == "abcdef"
    end

    test "an explicit convert still cuts identities and hash keys at the length limit" do
      long = "x" * 2000
      assert Logbuch.convert(Labeled.new(long), detail: :id).as_s == "#{"x" * 1024}… (+976 bytes)"
      noted = Logbuch.convert(Noted.new, detail: :id).as_s
      assert noted.starts_with?("#<Noted:0x")
      assert noted.ends_with?("x…")
      assert noted.size == 1025
      key = pair_keys(Logbuch.convert({Noted.new => 1}, detail: :full)).first
      assert key.starts_with?("#<Noted:0x")
      assert key.size == 1025
      assert key.ends_with?("x…")
    end
  end
{% end %}

# The printable ASCII bytes.
PRINTABLE = 0x20_u8...0x7f_u8

# The texts in the file at *path* that name logbuch, other than the names in
# *allowed*: the bytes around each `Logbuch` in it, as far as they are
# printable, such as the symbol `*Logbuch::Tracer#convert<…>` or the type name
# `Logbuch::Tracer` that the compiler keeps for every type in the program.
def other_logbuch_names(path : String, allowed : Array(String)) : Array(String)
  bytes = File.read(path)
  names = [] of String
  offset = 0
  while index = bytes.byte_index("Logbuch", offset)
    start = index
    while start > 0 && PRINTABLE.includes?(bytes.byte_at(start - 1))
      start -= 1
    end
    finish = index
    while finish < bytes.bytesize && PRINTABLE.includes?(bytes.byte_at(finish))
      finish += 1
    end
    name = bytes.byte_slice(start, finish - start)
    names << name unless allowed.includes?(name)
    offset = finish
  end
  names
end

# The types a program built with `-Dlogbuch=off` still has: the public ones,
# which its code may name, and `Setting`, which they use. The compiler keeps
# the name of every type.
TYPES_LEFT_WITH_TRACING_OFF = %w[Configuration Detail Setting Settings Tracer]
  .flat_map { |name| ["Logbuch::#{name}", "Logbuch::#{name}.class"] }

describe CompiledOut do
  test "a program built with -Dlogbuch=off holds nothing of logbuch but the names of its types" do
    expected = "23\n1\n2\nnone left\n6\n"
    assert run_program("compiled_out", flags: ["logbuch=off"], args: [] of String) == expected
    assert other_logbuch_names(program_path("compiled_out", ["logbuch=off"]), TYPES_LEFT_WITH_TRACING_OFF).empty?
    # Built with tracing on, the same program has logbuch code, which the
    # check finds.
    assert run_program("compiled_out", args: [] of String) == expected
    assert !other_logbuch_names(program_path("compiled_out", [] of String), TYPES_LEFT_WITH_TRACING_OFF).empty?
  end
end
