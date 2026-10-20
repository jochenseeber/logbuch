require "file_utils"
require "log"
require "microtest"

include Microtest::DSL

# Collects log entries instead of printing them, so tests can assert on them.
# It writes directly, which tests rely on, and takes a lock, so traced calls
# in several threads can log at the same time.
class CaptureBackend < Log::Backend
  @lock = Mutex.new
  @entries = [] of Log::Entry

  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    @lock.synchronize { @entries << entry }
  end

  # Removes the entries collected so far.
  def clear : Nil
    @lock.synchronize { @entries.clear }
  end

  # A copy of the entries collected so far.
  def entries : Array(Log::Entry)
    @lock.synchronize { @entries.dup }
  end
end

LOG_BACKEND = CaptureBackend.new
Log.setup(&.bind("*", :trace, LOG_BACKEND))

# Returns the entries logged while the block runs.
def capture_log(&) : Array(Log::Entry)
  LOG_BACKEND.clear
  yield
  LOG_BACKEND.entries
end

# Returns what the block returns, run with `max_depth` set to *depth*, then
# sets `max_depth` back to its default.
def with_max_depth(depth : Int, &)
  Logbuch.configure { max_depth depth }
  begin
    yield
  ensure
    Logbuch.configure { max_depth Logbuch::MAX_DEPTH }
  end
end

# The keys of *value*, a hash logged as an array of key and value pairs, as
# the text of their log values.
def pair_keys(value : Log::Metadata::Value) : Array(String)
  value.as_a.map(&.as_a[0].to_s)
end

# The keys and the values of *value*, a hash logged as an array of key and
# value pairs.
def pair_parts(value : Log::Metadata::Value) : {Array(Log::Metadata::Value), Array(Log::Metadata::Value)}
  pairs = value.as_a.map(&.as_a)
  {pairs.map(&.[0]), pairs.map(&.[1])}
end

# One compiler run for a fixture, started in the background. Runs wait for a
# free slot, so only a few compile at once.
class FixtureRun
  # How many fixtures compile at once.
  SLOTS = Channel(Nil).new(Math.max(2, System.cpu_count.to_i // 2))

  @result : {Bool, String}? = nil
  @process : Process? = nil
  @done = Channel(Nil).new

  # Runs the compiler with *args*.
  def initialize(args : Array(String))
    spawn do
      SLOTS.send(nil)
      begin
        output = IO::Memory.new
        process = @process = Process.new("crystal", args, output: output, error: output)
        @result = {process.wait.success?, output.to_s}
      ensure
        SLOTS.receive
        @done.close
      end
    end
  end

  # Whether the fixture compiled, and the compiler output; waits for the run.
  def result : {Bool, String}
    @done.receive?
    @result || {false, "the compiler run for this fixture failed to start"}
  end

  # Stops the compiler if it is still running.
  def stop : Nil
    if (process = @process) && !process.terminated?
      process.terminate
    end
  end
end

# The fixture runs started so far, by compiler arguments.
FIXTURE_RUNS = {} of Array(String) => FixtureRun

# The fixtures that are programs to build and run, not code to compile.
PROGRAM_FIXTURES = File.join(__DIR__, "fixtures", "programs")

# Where the fixture programs are built; removed at exit.
PROGRAM_DIR = File.tempname("logbuch-programs").tap { |dir| Dir.mkdir_p(dir) }

# On macOS, Crystal links with mold, which Apple's clang rejects; naming a
# linker overrides that, as the rake tasks do.
LINK_ARGS = {% if flag?(:darwin) %} ["--link-flags=-fuse-ld=/usr/bin/ld"] {% else %} [] of String {% end %}

# Where the program fixture *name* built with *flags* is written, a file of
# its own for each set of flags, such as `settings` and `settings-logbuch=off`.
def program_path(name : String, flags : Array(String)) : String
  File.join(PROGRAM_DIR, ([name] + flags).join('-'))
end

# The compiler arguments the fixture at *path* names on its first line, such
# as `# build: --prelude=empty`, or none.
def build_args(path : String) : Array(String)
  first = File.open(path, &.gets) || ""
  first.starts_with?("# build: ") ? first.lchop("# build: ").split : [] of String
end

# The compiler arguments that check the fixture at *path*: a program is built
# into `PROGRAM_DIR`, anything else is compiled without generating code.
def fixture_args(path : String, flags : Array(String)) : Array(String)
  flag_args = flags.map { |flag| "-D#{flag}" } + build_args(path)
  if File.dirname(path) == PROGRAM_FIXTURES
    ["build", path, "-o", program_path(File.basename(path, ".cr"), flags)] + LINK_ARGS + flag_args
  else
    ["build", "--no-codegen", path] + flag_args
  end
end

# The compiler run for the fixture at *path*, started unless it was already.
def fixture_run(path : String, flags : Array(String)) : FixtureRun
  args = fixture_args(path, flags)
  FIXTURE_RUNS[args] ||= FixtureRun.new(args)
end

# Compiles `spec/fixtures/<fixture>.cr` without generating code and returns
# whether it succeeded, plus the compiler output (errors and warnings).
def compile_output(fixture : String, *, flags : Array(String) = [] of String) : {Bool, String}
  fixture_run(File.join(__DIR__, "fixtures", "#{fixture}.cr"), flags).result
end

# Compiles `spec/fixtures/compile_errors/<fixture>.cr` and returns the
# compiler output if compilation failed, or nil if it succeeded.
def compile_error(fixture : String, *, flags : Array(String) = [] of String) : String?
  success, output = compile_output("compile_errors/#{fixture}", flags: flags)
  success ? nil : output
end

# A fixture program that failed to build or to run.
class FixtureError < Exception
end

# A sample object that does not have the shape a spec expects, such as a chain
# shorter than the spec walks.
class SampleError < Exception
end

# The environment variables Logbuch reads.
LOGBUCH_VARIABLES = ["LOGBUCH_MAX_DEPTH", "LOGBUCH_MAX_CAP", "LOGBUCH_MAX_LENGTH"]

# The specs expect the built-in defaults, whatever the shell running them set.
LOGBUCH_VARIABLES.each { |name| ENV.delete(name) }

# Builds `spec/fixtures/programs/<fixture>.cr` once with the build *flags*,
# such as `logbuch=off`, runs it with *args*, with the Logbuch variables in
# *env* set and the others unset, and returns what it printed. Raises if it
# fails to build or to run.
def run_program(fixture : String, *, args : Array(String), env : Hash(String, String) = {} of String => String,
                flags : Array(String) = [] of String) : String
  success, output = fixture_run(File.join(PROGRAM_FIXTURES, "#{fixture}.cr"), flags).result
  raise FixtureError.new("#{fixture} failed to build:\n#{output}") unless success
  variables = LOGBUCH_VARIABLES.to_h { |name| {name, env[name]?} }
  printed = IO::Memory.new
  status = Process.run(program_path(fixture, flags), args, env: variables, output: printed, error: printed)
  raise FixtureError.new("#{fixture} failed:\n#{printed}") unless status.success?
  printed.to_s
end

# Run at exit so that spec files and sources required after this helper have
# finished their top-level initialization before the first test starts. Every
# fixture starts compiling first, and every compile-error fixture with
# `-Dlogbuch=off` too, so the tests that check one rarely wait; runs no test
# asked for are stopped at the end, even when the run raises.
at_exit do
  success = begin
    Dir.glob(File.join(__DIR__, "fixtures", "**", "*.cr")).sort.each do |path|
      fixture_run(path, [] of String)
    end
    Dir.glob(File.join(__DIR__, "fixtures", "compile_errors", "*.cr")).sort.each do |path|
      fixture_run(path, ["logbuch=off"])
    end
    Microtest.run
  ensure
    FIXTURE_RUNS.each_value(&.stop)
    FileUtils.rm_rf(PROGRAM_DIR)
  end
  exit(success ? 0 : 1)
end
