require "wait_group"

require "../spec_helper"
require "../../src/logbuch"

module Shared
  # A job list that several threads change under one lock.
  class Inbox
    include Logbuch::Annotations

    getter lock = Mutex.new
    getter jobs = [] of String

    def push(job : String) : Nil
      @lock.synchronize do
        @jobs << job
        # Clearing zeroes the slots, so an unlocked reader would read null
        # strings and crash.
        @jobs.clear if @jobs.size > 300
      end
    end

    @[Logged]
    def audit(@[LogAs(:full, converter: ->(jobs) { @lock.synchronize { jobs.dup } })] jobs : Array(String)) : Nil
    end

    @[Logged(result: ->(jobs) { @lock.synchronize { jobs.size } })]
    def pending : Array(String)
      @jobs
    end

    @[Logged(result: ->(_count) { raise ArgumentError.new("no") })]
    def broken_count : Int32
      7
    end
  end

  # A board whose notes are read under its own lock.
  @[Logbuch::Annotations::LogType]
  class Board
    include Logbuch::Annotations

    @[LogAs(:omit)]
    getter lock = Mutex.new

    @[LogAs(:full, converter: ->(notes) { @lock.synchronize { notes.dup } })]
    getter notes = ["call back"]
  end

  # A queue that takes its own lock to log itself.
  class JobQueue
    @lock = Mutex.new
    @jobs = [1, 2]

    def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
      @lock.synchronize { tracer.convert(@jobs) }
    end
  end
end

describe Threads do
  test "a parameter converter can read the argument under the receiver's lock" do
    inbox = Shared::Inbox.new
    inbox.push("a")
    inbox.push("b")
    entries = capture_log { inbox.audit(inbox.jobs) }
    assert entries[0].data[:args].as_h["jobs"].as_a.map(&.as_s) == ["a", "b"]
  end

  test "a converter that takes a lock the caller holds logs a placeholder instead of deadlocking" do
    inbox = Shared::Inbox.new
    entries = capture_log { inbox.lock.synchronize { inbox.audit(inbox.jobs) } }
    assert entries[0].data[:args].as_h["jobs"].as_s == "#<convert raised Sync::Error::Deadlock>"
  end

  test "a field converter can read the field under its object's lock" do
    assert Logbuch.convert(Shared::Board.new, detail: :full).as_h == {"notes" => Log::Metadata::Value.new([Log::Metadata::Value.new("call back")])}
  end

  test "a type's own to_trace can take its lock" do
    assert Logbuch.convert(Shared::JobQueue.new, detail: :full).as_a.map(&.as_i) == [1, 2]
  end

  test "a result converter changes the logged result" do
    inbox = Shared::Inbox.new
    inbox.push("a")
    entries = capture_log { assert inbox.pending == ["a"] }
    assert entries[1].data[:result].as_i == 1
  end

  test "a result converter that raises logs a placeholder and keeps the result" do
    entries = capture_log { assert Shared::Inbox.new.broken_count == 7 }
    assert entries[1].data[:result].as_s == "#<convert raised ArgumentError>"
  end

  test "bad result converters fail to compile" do
    assert compile_error("result_not_a_block").to_s.includes?("logbuch: result: takes a block in arrow notation with one parameter")
    assert compile_error("result_on_nil").to_s.includes?("logbuch: result: has no effect on Quiet#run, which logs no result")
    assert compile_error("result_on_omit").to_s.includes?("logbuch: result: has no effect on Quiet#run, which logs no result")
  end

  # A crash test: a read that does not take the writers' lock crashes the
  # process, so the test fails by never finishing.
  test "traced reads under the writers' lock do not crash with writers in other threads" do
    inbox = Shared::Inbox.new
    threads = Fiber::ExecutionContext::Parallel.new("shared-values", 8)
    group = WaitGroup.new(8)
    entries = capture_log do
      4.times { threads.spawn { 50_000.times { |job| inbox.push("job #{job}") } ensure group.done } }
      4.times { threads.spawn { 5_000.times { inbox.audit(inbox.jobs) } ensure group.done } }
      group.wait
    end
    assert entries.size == 2 * 4 * 5_000
  end
end
