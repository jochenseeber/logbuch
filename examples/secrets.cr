# Secrets: keep them out of the log with `@[LogAs(:omit)]`, mask them with
# `@[LogAs(:redacted)]`, or log a safe part of them with a converter.
#
#   crystal run examples/secrets.cr

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

class Credentials
  getter user : String

  # Annotations on `initialize` parameters apply to the instance variables they
  # set: the password never shows up, the token shows up as "***". With :full
  # next to :redacted, the token shows only at Full detail; a string field
  # without a detail of its own would show from Summary up.
  def initialize(@user : String, @[LogAs(:omit)] @password : String, @[LogAs(:full, :redacted)] @token : String)
  end
end

class PaymentCard
  getter holder : String

  # A converter masks the number itself, here down to the last four digits;
  # :redacted, which always logs "***", takes no converter.
  @[LogAs(converter: ->(number : String) { "****#{number[-4..]}" })]
  getter number : String

  def initialize(@holder : String, @number : String)
  end
end

class Bank
  @[Logged("logging in", :full)]
  def login(credentials : Credentials) : Bool
    true
  end

  @[Logged("charging a card")]
  def charge(
    card : PaymentCard,
    amount : Int32,
    @[LogAs(:omit)] cvv : String,
    @[LogAs(:redacted)] pin : String,
    @[LogAs(:summary, converter: ->(email : String) { email.sub(/\A[^@]+/, "***") })] receipt_to : String,
  ) : String
    "receipt-1"
  end

  # A hash key is logged at :id, so a card as a key shows only its identity.
  @[Logged("limiting cards")]
  def limit_cards(limits : Hash(PaymentCard, Int32)) : Nil
  end

  # A converter that raises does not stop the call; the log shows a
  # placeholder instead of the value.
  @[Logged("verifying a signature")]
  def verify(@[LogAs(:summary, converter: ->(signature : String) { raise ArgumentError.new("unreadable") })] signature : String) : Bool
    true
  end
end

bank = Bank.new

puts "# :omit leaves the password out, :redacted shows the token as ***:"
bank.login(Credentials.new("ada", "hunter2", "tok-123"))

puts "\n# Parameters: cvv omitted, pin redacted, card and email partly masked:"
bank.charge(PaymentCard.new("Ada Lovelace", "4111222233334444"), 4200, "123", "9876", "ada@example.com")

puts "\n# A card as a hash key logs its identity, so nothing of it shows:"
bank.limit_cards({PaymentCard.new("Ada Lovelace", "4111222233334444") => 50_000})

puts "\n# A converter that raises leaves a placeholder:"
bank.verify("sig")

puts "\n# inspect masks too, so p and string interpolation show no secret:"
puts Credentials.new("ada", "hunter2", "tok-123").inspect
puts PaymentCard.new("Ada Lovelace", "4111222233334444").inspect
