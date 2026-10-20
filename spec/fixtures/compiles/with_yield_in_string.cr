require "../../../src/logbuch"

# The words of `with … yield` inside a literal are no `with … yield`, and
# neither are the words of a literal and a `yield` after it.
class Builder
  include Logbuch::Annotations

  @[Logged]
  def build(&) : String
    yield "with self yield"
    "built with care and yield"
  end

  @[Logged]
  def percent(&) : String
    yield %q(with self yield)
    yield %(with (nested) yield)
    yield %Q(with #{object_id} yield)
    yield <<-TEXT
      with self
      yield
      TEXT
  end

  # A `"` in a char does not start a string.
  @[Logged]
  def quoted(&) : String
    text = '"'.to_s + "with self"
    yield text
  end

  @[Logged]
  def symbol(&) : Symbol
    yield :"with self yield"
  end

  # The strings in an interpolation do not end the string around it.
  @[Logged]
  def interpolated(&) : String
    text = "#{"x".empty? ? "with ice" : "plain"} and #{{a: "with ice"}[:a]}"
    yield text
  end

  @[Logged]
  def matches(&) : String
    matched = !!(object_id.to_s =~ /with self/)
    yield matched.to_s
  end

  @[Logged]
  def command(&) : String
    text = `echo with #{object_id}`
    yield text
  end
end

builder = Builder.new
builder.build { |text| text }
builder.percent { |text| text }
builder.quoted { |text| text }
builder.symbol { |text| text }
builder.interpolated { |text| text }
builder.matches { |text| text }
builder.command { |text| text }
