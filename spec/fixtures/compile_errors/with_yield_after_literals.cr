require "../../../src/logbuch"

# A `with … yield` among literals that the check blanks is still found.
class Offender
  include Logbuch::Annotations

  @[Logged]
  def build(&) : Nil
    quote = '"'
    plain = "#{quote ? "with" : "without"} x" =~ /with #{quote} x/
    `echo #{plain}`
    with self yield
  end

  def add(value : Int32) : Nil
  end
end

Offender.new.build { add 1 }
