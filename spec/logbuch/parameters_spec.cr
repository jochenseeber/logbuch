require "../spec_helper"
require "../support/samples"

class Payments
  include Logbuch::Annotations

  @[Logged(:full)]
  def pay(card : Card, @[LogAs(:omit)] number : String, @[LogAs(:id)] other : Card) : Bool
    true
  end

  @[Logged]
  def login(
    user : String,
    @[LogAs(:redacted)] password : String,
    @[LogAs(converter: ->(value : String) { "****#{value[-4..]}" })] card : String,
    @[LogAs(:summary, converter: ->(value) { value.upcase })] code : String,
    @[LogAs(:summary, converter: ->(value : String) { raise ArgumentError.new("no") })] token : String,
  ) : Bool
    true
  end

  @[Logged(:omit)]
  def unlock(@[LogAs(:redacted)] pin : String) : Bool
    true
  end

  @[Logged(:id)]
  def charge(@[LogAs(:redacted)] card : Card) : Bool
    true
  end

  @[Logged(:omit)]
  def unlock_logged(@[LogAs(:summary, :redacted)] pin : String) : Bool
    true
  end

  @[Logged(:full)]
  def charge_by_id(@[LogAs(:id, :redacted)] card : Card) : Bool
    true
  end

  @[Logged(:omit)]
  def reveal(@[LogAs(Logbuch::Detail::Id)] card : Card, @[LogAs(::Logbuch::Detail::Summary, :redacted)] pin : String) : Bool
    true
  end

  @[Logged(:full)]
  def measure(@[LogAs(converter: ->(text : String) { text.size })] text : String, @[LogAs(length: 3)] note : String) : Bool
    true
  end

  @[Logged]
  def search(@[LogAs(:summary, cap: 2)] terms : Array(String), @[LogAs(:summary, length: 3)] query : String) : Int32
    terms.size
  end

  @[Logged(:full)]
  def splat(@[LogAs(:omit)] *secrets : String) : Int32
    secrets.size
  end

  @[Logged(:full)]
  def double_splat(@[LogAs(:omit)] **secrets) : Int32
    secrets.size
  end
end

describe ParameterDetail do
  test "omit drops the argument even under full" do
    args = capture_log { Payments.new.pay(Card.new, "4111", Card.new) }[0].data[:args].as_h
    assert !args.has_key?("number")
    assert args["card"].as_h.has_key?("tags")
    assert args["other"].as_s == "c1"
  end

  test "redact and a converter change the logged argument" do
    args = capture_log { Payments.new.login("u", "secret", "4111222233334444", "abc", "t") }[0].data[:args].as_h
    assert args["user"].as_s == "u"
    assert args["password"].as_s == "***"
    assert args["card"].as_s == "****4444"
    assert args["code"].as_s == "ABC"
    assert args["token"].as_s == "#<convert raised ArgumentError>"
  end

  test "redact keeps the method's detail" do
    assert capture_log { Payments.new.unlock("1234") }[0].data[:args]?.nil?
    args = capture_log { Payments.new.charge(Card.new) }[0].data[:args].as_h
    assert args["card"].as_s == "***"
  end

  test "a detail next to :redacted sets the detail of the masked argument" do
    assert capture_log { Payments.new.unlock_logged("1234") }[0].data[:args].as_h["pin"].as_s == "***"
    assert capture_log { Payments.new.charge_by_id(Card.new) }[0].data[:args].as_h["card"].as_s == "***"
  end

  test "a parameter's detail can be a Logbuch::Detail path" do
    args = capture_log { Payments.new.reveal(Card.new, "1234") }[0].data[:args].as_h
    assert args["card"].as_s == "c1"
    assert args["pin"].as_s == "***"
  end

  test "a converter or a limit alone keeps the method's detail" do
    args = capture_log { Payments.new.measure("hello", "word") }[0].data[:args].as_h
    assert args["text"].as_i == 5
    assert args["note"].as_s == "wor… (+1 bytes)"
  end

  test "LogAs on a method fails to compile" do
    assert compile_error("redact_on_method").to_s.includes?("logbuch: @[LogAs] goes on parameters and fields; trace Offender#go with @[Logged]")
  end

  test "a parameter annotation sets the limits for its argument" do
    args = capture_log { Payments.new.search(["abcd", "ef", "gh"], "word") }[0].data[:args].as_h
    assert args["terms"].as_a.map(&.as_s) == ["abcd", "ef", "… 1 more"]
    assert args["query"].as_s == "wor… (+1 bytes)"
  end

  test "omit drops splat and double splat arguments" do
    entries = capture_log do
      assert Payments.new.splat("a", "b") == 2
      assert Payments.new.double_splat(a: "x") == 1
    end
    assert entries[0].data[:args]?.nil?
    assert entries[2].data[:args]?.nil?
  end

  test "two LogAs, two details or method options on a parameter fail to compile" do
    assert compile_error("two_param_annotations").to_s.includes?("logbuch: parameter name of Offender#go has more than one @[LogAs]")
    assert compile_error("log_as_two_details").to_s.includes?("logbuch: @[LogAs] takes one detail, and :redacted and items(...) at most once, on parameter name of Offender#go")
    assert compile_error("param_options").to_s.includes?("logbuch: level: and timing: are only allowed on methods")
    assert compile_error("trace_on_parameter").to_s.includes?("logbuch: @[Logged] goes on methods; use @[LogAs] on parameter name of Offender#go")
  end
end
