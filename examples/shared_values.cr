# Values shared between threads: logbuch reads what it logs without a lock, so
# a value that other threads change is logged under the lock they take, named
# with `lock:`. Lines carry no fiber name unless the fiber puts it in the log
# context.
#
#   crystal run examples/shared_values.cr

require "wait_group"

require "../src/logbuch"

# The annotations without the `Logbuch::Annotations::` prefix.
include Logbuch::Annotations

# Prints the log context too, which holds the fiber name set below.
Log.define_formatter ExampleFormat, "#{severity} #{source(after: ": ")}#{message}#{data(before: " -- ")}#{context(before: " -- context: ")}"
Log.setup(:trace, Log::IOBackend.new(formatter: ExampleFormat, dispatcher: :sync))

# A queue whose fields are converted under its own lock, so it is safe
# wherever it is logged. The lock is a field like any other; `:omit` keeps
# its internals out of the log.
@[LogType(lock: @lock)]
class JobQueue
  @[LogAs(:omit)]
  @lock = Sync::Mutex.new
  @jobs = [] of String

  def push(job : String) : Nil
    @lock.synchronize { @jobs << job }
  end

  def sort : Nil
    @lock.synchronize { @jobs.sort! }
  end
end

class Dispatcher
  getter lock = Sync::Mutex.new
  getter jobs = [] of String

  def add(job : String) : Nil
    @lock.synchronize { @jobs << job }
  end

  def sort : Nil
    @lock.synchronize { @jobs.sort! }
  end

  # The queue logs itself under its own lock.
  @[Logged("handing over a queue", :full)]
  def hand_over(queue : JobQueue) : Nil
  end

  # The arguments are converted while the dispatcher's lock is held.
  @[Logged("auditing the jobs", lock: @lock)]
  def audit(jobs : Array(String)) : Nil
  end

  # The result converter runs under the lock too.
  @[Logged("listing pending jobs", lock: @lock, result: ->(jobs) { jobs.size })]
  def pending : Array(String)
    @jobs
  end
end

dispatcher = Dispatcher.new
queue = JobQueue.new

# Four threads fill the queue and the job list.
threads = Fiber::ExecutionContext::Parallel.new("writers", 4)
group = WaitGroup.new(4)
4.times do |writer|
  threads.spawn do
    3.times do |index|
      dispatcher.add("job #{writer}-#{index}")
      queue.push("job #{writer}-#{index}")
    end
  ensure
    group.done
  end
end
group.wait

# The threads finish in any order; sorting makes the output the same on every run.
dispatcher.sort
queue.sort

puts "-- a type whose fields are converted under its own lock"
dispatcher.hand_over(queue)

puts "\n-- a method that converts its arguments under the lock"
dispatcher.audit(dispatcher.jobs)

puts "\n-- a result converter, run under the lock"
dispatcher.pending

puts "\n-- called while the caller holds the lock: logbuch does not take it again"
dispatcher.lock.synchronize { dispatcher.audit(dispatcher.jobs) }

puts "\n-- a fiber that puts its name in the log context: every line it writes carries it"
finished = Channel(Nil).new
spawn(name: "auditor") do
  Log.context.set(fiber: Fiber.current.name)
  dispatcher.audit(dispatcher.jobs.first(2))
ensure
  finished.send(nil)
end
finished.receive
