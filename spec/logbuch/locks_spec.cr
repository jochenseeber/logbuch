require "../spec_helper"
require "../../src/logbuch"

# Logs whether *lock* is held by the fiber converting it.
class HeldProbe
  def initialize(@lock : Sync::Mutex)
  end

  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new(@lock.__logbuch_held?)
  end
end

# A lock that is not a `Sync::Mutex`: it counts how often it was taken.
class CountingLock
  getter count = 0

  def synchronize(&)
    @count += 1
    yield
  end
end

# Raised by `StrictLock` when it is taken again before it is released.
class LockTakenTwice < Exception
end

# A lock that counts how often it was taken and raises when it is taken again
# before it is released, where a mutex that is not reentrant would deadlock.
class StrictLock
  getter count = 0
  @held = false

  def synchronize(&)
    raise LockTakenTwice.new("taken twice") if @held
    @count += 1
    @held = true
    begin
      yield
    ensure
      @held = false
    end
  end
end

# Locked by a lock that cannot be taken twice, with an `:id` field and a link
# that may lead back to the record itself.
@[Logbuch::Annotations::LogType(lock: @lock)]
class StrictRecord
  include Logbuch::Annotations

  getter lock = StrictLock.new

  @[LogAs(:id)]
  getter name = "r1"

  @[LogAs(:summary)]
  property link : StrictRecord?
end

# A lock that `lock:` names by a constant.
SHARED_LOCK = Sync::Mutex.new

@[Logbuch::Annotations::LogType(lock: SHARED_LOCK)]
class SharedRecord
  getter probe = HeldProbe.new(SHARED_LOCK)
end

# Locked, with the field that holds the lock logged like any other.
@[Logbuch::Annotations::LogType(lock: @lock)]
class NamedLockRecord
  getter lock = Sync::Mutex.new
  getter name = "n"
end

# Locked, with the field that holds the lock left out.
@[Logbuch::Annotations::LogType(lock: @lock)]
class OmittedLockRecord
  include Logbuch::Annotations

  @[LogAs(:omit)]
  getter lock = Sync::Mutex.new
  getter name = "o"
end

@[Logbuch::Annotations::LogType(lock: @lock)]
class LockedRecord
  getter lock = Sync::Mutex.new
  getter probe : HeldProbe

  def initialize
    @probe = HeldProbe.new(@lock)
  end
end

# Holds a lock without converting itself, so only a converter can tell
# whether the lock is held while it runs.
class LockHolder
  getter lock : Sync::Mutex

  def initialize(@lock : Sync::Mutex)
  end
end

# Takes a lock that a class variable holds.
class LockedRegistry
  include Logbuch::Annotations

  @@lock = CountingLock.new

  def self.lock : CountingLock
    @@lock
  end

  @[Logged(lock: @@lock)]
  def self.register(name : String) : String
    name
  end
end

class LockedService
  include Logbuch::Annotations

  getter lock = Sync::Mutex.new
  getter other_lock = CountingLock.new
  getter record = LockedRecord.new

  @[Logged(lock: @lock)]
  def take(probe : HeldProbe) : Nil
  end

  @[Logged(lock: @lock)]
  def held_while_running : Bool
    @lock.__logbuch_held?
  end

  @[Logged(lock: @lock)]
  def give : HeldProbe
    HeldProbe.new(@lock)
  end

  @[Logged(:full, lock: @record.lock)]
  def give_record : LockedRecord
    @record
  end

  @[Logged(lock: @lock, result: ->(holder) { holder.lock.__logbuch_held? })]
  def give_holder : LockHolder
    LockHolder.new(@lock)
  end

  @[Logged(lock: @lock)]
  def take_holder(@[LogAs(converter: ->(holder : LockHolder) { holder.lock.__logbuch_held? })] holder : LockHolder) : Nil
  end

  @[Logged(lock: SHARED_LOCK)]
  def take_shared(probe : HeldProbe) : Nil
  end

  @[Logged(lock: @other_lock)]
  def count(value : Int32) : Int32
    value
  end
end

# A lock that cannot be taken.
class BrokenLock
  def synchronize(&)
    raise IO::Error.new("lock broken")
  end
end

# Converts its arguments and results under locks that raise.
class BrokenLockService
  include Logbuch::Annotations

  getter strict = StrictLock.new
  @broken = BrokenLock.new

  @[Logged(lock: @broken)]
  def double(x : Int32) : Int32
    x * 2
  end

  @[Logged(lock: @broken, slow: {ms: 1, level: :warn, args: true})]
  @[LogAccept(KeyError)]
  def find(key : String) : Nil
    sleep 5.milliseconds
    raise KeyError.new(key)
  end

  @[Logged(lock: @strict)]
  def inner(x : Int32) : Int32
    x + 1
  end

  # Calls `inner` while holding the lock it converts under, which a lock
  # that is not reentrant refuses.
  def outer(x : Int32) : Int32
    @strict.synchronize { inner(x) }
  end
end

{% unless %w[off 0].includes?(flag?(:logbuch)) %}
  describe Locks do
    test "lock: holds the lock while the arguments are converted" do
      service = LockedService.new
      entries = capture_log { service.take(HeldProbe.new(service.lock)) }
      assert entries[0].data[:args].as_h["probe"].as_bool == true
    end

    test "lock: holds the lock while the result is converted" do
      entries = capture_log { LockedService.new.give }
      assert entries[1].data[:result].as_bool == true
    end

    test "lock: does not hold the lock while the method runs" do
      assert LockedService.new.held_while_running == false
    end

    test "a call made while the caller holds the lock logs under it" do
      service = LockedService.new
      entries = capture_log do
        service.lock.synchronize { service.take(HeldProbe.new(service.lock)) }
      end
      assert entries[0].data[:args].as_h["probe"].as_bool == true
    end

    test "a value locked by its type, converted under the same lock, is logged" do
      entries = capture_log { LockedService.new.give_record }
      assert entries[1].data[:result].as_h["probe"].as_bool == true
    end

    test "lock: holds the lock while the result: converter runs" do
      entries = capture_log { LockedService.new.give_holder }
      assert entries[1].data[:result].as_bool == true
    end

    test "lock: holds the lock while a parameter's converter: runs" do
      service = LockedService.new
      entries = capture_log { service.take_holder(LockHolder.new(service.lock)) }
      assert entries[0].data[:args].as_h["holder"].as_bool == true
    end

    test "lock: takes a class variable" do
      taken = LockedRegistry.lock.count
      entries = capture_log { assert LockedRegistry.register("a") == "a" }
      assert entries.map(&.message) == [">LockedRegistry.register", "<LockedRegistry.register"]
      assert LockedRegistry.lock.count - taken == 2
    end

    test "lock: takes a constant" do
      entries = capture_log { LockedService.new.take_shared(HeldProbe.new(SHARED_LOCK)) }
      assert entries[0].data[:args].as_h["probe"].as_bool == true
    end

    test "lock: takes any lock with a synchronize method" do
      service = LockedService.new
      capture_log { service.count(1) }
      assert service.other_lock.count == 2
    end

    test "a lock that raises leaves a placeholder, and the method runs and returns" do
      result = 0
      entries = capture_log { result = BrokenLockService.new.double(2) }
      assert result == 4
      assert entries.map(&.message) == [">BrokenLockService#double", "<BrokenLockService#double"]
      assert entries[0].data[:args].as_s == "#<lock raised IO::Error>"
      assert entries[1].data[:result].as_s == "#<lock raised IO::Error>"
    end

    test "a lock that raises leaves a placeholder for the arguments of a slow accepted exception" do
      timing_off = {{ %w[off 0].includes?(flag?(:logbuch_timing)) }}
      ::Log.for("broken_lock_service").level = :warn
      raised = nil
      entries = capture_log do
        BrokenLockService.new.find("k")
      rescue error
        raised = error
      end
      assert raised.is_a?(KeyError)
      if timing_off
        assert entries.empty?
      else
        assert entries.map(&.message) == ["<BrokenLockService#find"]
        assert entries[0].data[:args].as_s == "#<lock raised IO::Error>"
        assert entries[0].data[:result].as_h["type"].as_s == "KeyError"
      end
    ensure
      ::Log.for("broken_lock_service").level = :trace
    end

    test "a lock the caller holds already, which refuses to be taken twice, leaves a placeholder" do
      service = BrokenLockService.new
      result = 0
      entries = capture_log { result = service.outer(1) }
      assert result == 2
      assert entries[0].data[:args].as_s == "#<lock raised LockTakenTwice>"
      assert entries[1].data[:result].as_s == "#<lock raised LockTakenTwice>"
    end

    test "lock: needs an expression that names the lock" do
      assert compile_error("lock_literal").to_s.includes?("logbuch: lock: takes the lock to hold")
    end
  end
{% end %}

describe TypeLocks do
  test "LogType(lock:) holds the lock while the fields are converted" do
    value = Logbuch.convert(LockedRecord.new, detail: :full)
    assert value.as_h["probe"].as_bool == true
  end

  test "LogType(lock:) takes a constant" do
    value = Logbuch.convert(SharedRecord.new, detail: :full)
    assert value.as_h == {"probe" => Log::Metadata::Value.new(true)}
  end

  test "LogType(lock:) logs the field that holds the lock like any other, unless it is omitted" do
    assert Logbuch.convert(NamedLockRecord.new, detail: :full).as_h.keys == ["lock", "name"]
    assert Logbuch.convert(NamedLockRecord.new, detail: :summary).as_h.keys == ["name"]
    assert Logbuch.convert(OmittedLockRecord.new, detail: :full).as_h.keys == ["name"]
  end

  test "LogType(lock:) converts under a lock the fiber holds already" do
    record = LockedRecord.new
    value = record.lock.synchronize { Logbuch.convert(record, detail: :full) }
    assert value.as_h["probe"].as_bool == true
  end

  test "LogType(lock:) holds the lock while the id fields are read, but not again for a cycle" do
    record = StrictRecord.new
    record.link = record
    value = Logbuch.convert(record, detail: :summary).as_h
    assert value["link"].as_s == "r1"
    assert record.lock.count == 1
    assert Logbuch.convert(record, detail: :id).as_s == "r1"
    assert record.lock.count == 2
  end

  test "LogType takes no option but lock:, log:, inspect: and stacktrace:" do
    assert compile_error("type_unknown_option").to_s.includes?("logbuch: @[LogType] takes only lock:, log: and inspect:, and stacktrace: on an exception class, such as @[LogType(lock: @lock)], on Offender")
  end

  test "LogType(lock:) needs an expression that names the lock, on a type never converted too" do
    assert compile_error("type_lock_literal").to_s.includes?("logbuch: lock: takes the lock to hold while converting, such as lock: @lock, on @[LogType] of Offender")
  end
end
