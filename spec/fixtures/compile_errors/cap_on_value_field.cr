require "../../../src/logbuch"
require "uri"

class Offender
  include Logbuch::Annotations

  @[LogAs(cap: 3)]
  @home : URI = URI.parse("https://example.com")
end

Offender.new
