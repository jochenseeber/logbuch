# Runs the steps its arguments name, in order, and prints the settings and the
# warnings Logbuch logs:
#
# - `show` prints `Logbuch.settings`
# - `set:NAME=value` sets an environment variable
# - `configure:max_depth=3`, `configure:max_depth=3,env=false` and
#   `configure:use_env=false` call `Logbuch.configure` with one setter
# - `failing_log` makes logging raise
require "../../../src/logbuch"

# Prints each entry as `WARN logbuch: message`.
class PrintBackend < Log::Backend
  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    puts "#{entry.severity.label} #{entry.source}: #{entry.message}"
  end
end

# Raises on every entry.
class FailingBackend < Log::Backend
  def initialize
    super(:direct)
  end

  def write(entry : Log::Entry) : Nil
    raise IO::Error.new("the log is gone")
  end
end

Log.setup(&.bind("*", :warn, PrintBackend.new))

def configure(argument : String) : Nil
  name, _, rest = argument.partition("=")
  value, _, env = rest.partition(",env=")
  switch = env.empty? ? nil : env == "true"
  Logbuch.configure do
    case name
    when "use_env"    then use_env(value == "true")
    when "max_depth"  then max_depth(value.to_u32, env: switch)
    when "max_cap"    then max_cap(value.to_u32, env: switch)
    when "max_length" then max_length(value.to_u32, env: switch)
    else                   raise ArgumentError.new("unknown setting #{name}")
    end
  end
end

ARGV.each do |step|
  command, _, argument = step.partition(":")
  case command
  when "show"
    puts Logbuch.settings
  when "set"
    name, _, value = argument.partition("=")
    ENV[name] = value
  when "configure"
    configure(argument)
  when "failing_log"
    Log.setup(&.bind("*", :warn, FailingBackend.new))
  else
    raise ArgumentError.new("unknown step #{step}")
  end
end
