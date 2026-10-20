require "../spec_helper"
require "../../src/logbuch"

AUDIT_LOG = ::Log.for("audit")

module Sources
  Log = ::Log.for("sources")

  class Shop
    include Logbuch::Annotations

    @[Logged]
    def plain : Int32
      1
    end

    @[Logged(log: "billing.export")]
    def export : Int32
      2
    end

    @[Logged(log: ".place")]
    def place : Int32
      3
    end

    @[Logged(log: AUDIT_LOG)]
    def audit : Int32
      4
    end

    @[Logged(log: ".lookup")]
    def self.lookup : Int32
      5
    end
  end
end

class Unnamed
  include Logbuch::Annotations

  @[Logged(log: ".child")]
  def child : Int32
    1
  end
end

@[Logbuch::Annotations::LogType(log: "payments")]
class PaymentDesk
  include Logbuch::Annotations

  @[Logged]
  def pay : Int32
    1
  end

  @[Logged(log: ".refund")]
  def refund : Int32
    2
  end
end

class CardDesk < PaymentDesk
  include Logbuch::Annotations

  @[Logged]
  def charge : Int32
    3
  end
end

@[Logbuch::Annotations::LogType(log: ".io")]
class Disk
  include Logbuch::Annotations

  @[Logged]
  def read : Int32
    1
  end
end

class Disk::Cache < Disk
  include Logbuch::Annotations

  @[Logged]
  def hit : Int32
    2
  end
end

class LateLog
  include Logbuch::Annotations

  @[Logged]
  def run : Int32
    1
  end
end

@[Logbuch::Annotations::LogType(log: "late")]
class LateLog
end

@[Logbuch::Annotations::LogType(log: AUDIT_LOG)]
module Audited
  include Logbuch::Annotations

  @[Logged]
  def check : Int32
    1
  end
end

class AuditedRecord
  include Logbuch::Annotations

  include Audited

  @[Logged]
  def store : Int32
    2
  end
end

class Register
  include Logbuch::Annotations

  @[Logged]
  def total : Int32
    1
  end
end

# Inherits `Register#total` and has a `Log` of its own.
class TillRegister < Register
  include Logbuch::Annotations

  Log = ::Log.for("till")

  @[Logged]
  def open : Int32
    2
  end
end

# Inherits `Register#total` and has a `@[LogType(log:)]` of its own.
@[Logbuch::Annotations::LogType(log: "kiosk")]
class KioskRegister < Register
  include Logbuch::Annotations

  @[Logged]
  def open : Int32
    3
  end
end

class Terminal
  include Logbuch::Annotations

  Log = ::Log.for("terminals")
end

# Defines no `Log`, so its parent's is used.
class PosTerminal < Terminal
  include Logbuch::Annotations

  @[Logged]
  def scan : Int32
    1
  end
end

# The sources of the lines the block logs.
def sources(&) : Array(String)
  capture_log { yield }.map(&.source).uniq!
end

describe LogSources do
  test "a method logs to the type's log without log:" do
    assert sources { Sources::Shop.new.plain } == ["sources"]
  end

  test "log: takes a source name" do
    assert sources { Sources::Shop.new.export } == ["billing.export"]
  end

  test "log: takes a name below the type's log" do
    assert sources { Sources::Shop.new.place } == ["sources.place"]
    assert sources { Sources::Shop.lookup } == ["sources.lookup"]
    assert sources { Unnamed.new.child } == ["unnamed.child"]
  end

  test "log: takes a constant that holds a log" do
    assert sources { Sources::Shop.new.audit } == ["audit"]
  end

  test "LogType(log:) sets the log of the type and its subclasses" do
    assert sources { PaymentDesk.new.pay } == ["payments"]
    assert sources { PaymentDesk.new.refund } == ["payments.refund"]
    assert sources { CardDesk.new.charge } == ["payments"]
  end

  test "a LogType(log:) name with a dot is below each type's own log" do
    assert sources { Disk.new.read } == ["disk.io"]
    assert sources { Disk::Cache.new.hit } == ["disk.cache.io"]
  end

  test "LogType(log:) counts on any declaration of the type" do
    assert sources { LateLog.new.run } == ["late"]
  end

  test "LogType(log:) on a module applies to the types that include it" do
    record = AuditedRecord.new
    assert sources { record.check } == ["audit"]
    assert sources { record.store } == ["audit"]
  end

  test "an inherited method logs to its defining type's log, whatever log the subclass has" do
    assert sources { TillRegister.new.total } == ["register"]
    assert sources { TillRegister.new.open } == ["till"]
    assert sources { KioskRegister.new.total } == ["register"]
    assert sources { KioskRegister.new.open } == ["kiosk"]
  end

  test "a Log a parent class defines is the log of a subclass's methods" do
    assert sources { PosTerminal.new.scan } == ["terminals"]
  end

  test "invalid log: options fail to compile" do
    assert compile_error("log_not_a_name").to_s.includes?("logbuch: log: takes a constant that holds a Log, or a source name")
    assert compile_error("log_empty_name").to_s.includes?("logbuch: log: takes a source name")
    assert compile_error("log_empty_string").to_s.includes?(%(logbuch: log: takes a source name, such as "shop.checkout", or one below the type's log, such as ".place", on Offender#go))
    assert compile_error("log_type").to_s.includes?("logbuch: log: takes a constant that holds a Log or a source name, not the type String, on Offender#go")
    assert compile_error("log_undefined").to_s.includes?("logbuch: log: MISSING_LOG is not defined, on Offender#go")
    assert compile_error("log_not_a_log").to_s.includes?("logbuch: log: takes a constant that holds a Log, but NOT_A_LOG is \"audit\", on Offender#go")
    assert compile_error("log_computed_not_a_log").to_s.includes?("logbuch: log: takes a constant that holds a Log, not a String")
    assert compile_error("type_log_computed_not_a_log").to_s.includes?("logbuch: log: takes a constant that holds a Log, not a String")
    assert compile_error("type_log_type").to_s.includes?("logbuch: log: takes a constant that holds a Log or a source name, not the type String, on @[LogType] of Offender")
  end

  test "log: options are checked with -Dlogbuch=off too" do
    assert compile_error("log_type", flags: ["logbuch=off"]).to_s.includes?("not the type String")
    assert compile_error("type_log_type", flags: ["logbuch=off"]).to_s.includes?("not the type String")
  end
end
