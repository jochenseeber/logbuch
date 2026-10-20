require "../../../src/logbuch"

# Opted in to field logging only by the `@[LogAs]` on a field.
class Account
  @[Logbuch::Annotations::LogAs(:id)]
  getter code = "a-1"
end

class Offender
  include Logbuch::Annotations

  @[Logged]
  def go(@[LogAs(length: 3)] account : Account) : Nil
  end
end

Offender.new.go(Account.new)
