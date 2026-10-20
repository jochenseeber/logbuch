require "array"
require "atomic"
require "char"
require "enum"
require "env"
require "exception"
require "io"
require "log"
require "mutex"
require "static_array"
require "string"
require "tuple"

require "./limits"

module Logbuch
  # :nodoc:
  #
  # A run-time setting. Adding one means adding a member here, its default and
  # maximum below, a getter to `Settings` and a setter to `Configuration`.
  enum Setting
    MaxDepth
    MaxCap
    MaxLength

    # The value it has unless code or its variable sets one.
    def default : UInt32
      case self
      in .max_depth?  then MAX_DEPTH
      in .max_cap?    then MAX_CAP
      in .max_length? then MAX_LENGTH
      end
    end

    # The largest value it takes; the smallest is 0.
    def maximum : UInt32
      max_depth? ? DEPTH_CEILING : UInt32::MAX
    end

    # Its name in code, such as `max_depth`.
    def key : String
      to_s.underscore
    end

    # The environment variable that overrides it, such as `LOGBUCH_MAX_DEPTH`.
    def variable : String
      "LOGBUCH_#{key.upcase}"
    end
  end

  # :nodoc:
  #
  # The number of settings: the arrays that hold one value per setting, in
  # the order of `Setting`, have this size.
  SETTING_COUNT = 3

  {% unless Setting.constants.size == SETTING_COUNT %}
    {% raise "logbuch: SETTING_COUNT must be the number of members of Logbuch::Setting" %}
  {% end %}

  # The limits a conversion starts with, as `Logbuch.settings` returns them.
  # A `Settings` never changes: `Logbuch.configure` replaces it with a new
  # one.
  class Settings
    # :nodoc:
    def initialize(@values : StaticArray(UInt32, SETTING_COUNT))
    end

    # The nesting depth of objects, structs and collections in one traced
    # value; deeper ones are logged as their identity, such as
    # `"o-17"`. From 0 to `DEPTH_CEILING`, `MAX_DEPTH` by default, and
    # `LOGBUCH_MAX_DEPTH` overrides it.
    def max_depth : UInt32
      @values[Setting::MaxDepth.value]
    end

    # The items logged from one collection; the rest are counted.
    # `MAX_CAP` by default, and `LOGBUCH_MAX_CAP` overrides it.
    def max_cap : UInt32
      @values[Setting::MaxCap.value]
    end

    # The characters logged from one string, and from the `inspect` text of a
    # value; the rest are counted. `MAX_LENGTH` by default, and
    # `LOGBUCH_MAX_LENGTH` overrides it.
    def max_length : UInt32
      @values[Setting::MaxLength.value]
    end

    # Writes the settings as `max_depth: 16, max_cap: 100, max_length: 1024`.
    def to_s(io : IO) : Nil
      Setting.each do |setting|
        io << ", " unless setting.value == 0
        io << setting.key << ": " << @values[setting.value]
      end
    end

    # Writes the settings as `#<Logbuch::Settings max_depth: 16, …>`.
    def inspect(io : IO) : Nil
      io << "#<" << self.class.name << ' '
      to_s(io)
      io << '>'
    end
  end

  # The receiver of the block `Logbuch.configure` runs, which changes the
  # settings it names and leaves the others as they are.
  #
  # ```
  # Logbuch.configure do
  #   max_depth 3
  #   max_length 256, env: false
  # end
  # ```
  #
  # Each setting has an environment variable, such as `LOGBUCH_MAX_DEPTH`,
  # which overrides the value set here; `use_env false`, or `env: false` on
  # one setter, switches that off. A program built with `-Dlogbuch=off` only
  # type-checks the block and keeps the defaults.
  class Configuration
    # The values set in code, nil where none is.
    @values = StaticArray(UInt32?, SETTING_COUNT).new(nil)

    # Whether each setting reads its variable, nil where nothing said.
    @env = StaticArray(Bool?, SETTING_COUNT).new(nil)

    # Whether the settings read their variables at all, nil where nothing said.
    @use_env : Bool? = nil

    # :nodoc:
    def initialize
    end

    # Sets `Settings#max_depth`, from 0 to `DEPTH_CEILING`. `env: false` makes
    # it ignore `LOGBUCH_MAX_DEPTH`, and `env: true` makes it read that again.
    # Takes any integer type, such as an `Int32` variable, and raises
    # `ArgumentError` for a value out of range, a negative one included.
    def max_depth(value : Int, *, env : Bool? = nil) : Nil
      set(Setting::MaxDepth, value, env)
    end

    # Sets `Settings#max_cap`, from 0 to `UInt32::MAX`, and switches
    # `LOGBUCH_MAX_CAP` like `#max_depth`.
    def max_cap(value : Int, *, env : Bool? = nil) : Nil
      set(Setting::MaxCap, value, env)
    end

    # Sets `Settings#max_length`, from 0 to `UInt32::MAX`, and switches
    # `LOGBUCH_MAX_LENGTH` like `#max_depth`.
    def max_length(value : Int, *, env : Bool? = nil) : Nil
      set(Setting::MaxLength, value, env)
    end

    # Whether the settings read their environment variables: `use_env false`
    # makes every setting ignore its variable, also one applied already, and
    # `use_env true` reads them again, except where a setter said `env: false`.
    def use_env(enabled : Bool) : Nil
      @use_env = enabled
    end

    # :nodoc:
    #
    # Runs the block with this configuration as its receiver and returns it.
    # `Logbuch.configure` hands it its block; with `-Dlogbuch=off` it only
    # types the call.
    def __dsl(&) : Configuration
      with self yield
      self
    end

    # :nodoc:
    #
    # This configuration with what *changes* set on top.
    def merge(changes : Configuration) : Configuration
      merged = Configuration.new
      merged.merge_values(self, changes)
      merged
    end

    # :nodoc:
    #
    # The value of *setting* set in code, or nil.
    def value(setting : Setting) : UInt32?
      @values[setting.value]
    end

    # :nodoc:
    #
    # Whether *setting* reads its variable.
    def env?(setting : Setting) : Bool
      @use_env != false && @env[setting.value] != false
    end

    protected def merge_values(base : Configuration, changes : Configuration) : Nil
      Setting.each do |setting|
        index = setting.value
        @values[index] = changes.@values[index] || base.@values[index]
        env = changes.@env[index]
        @env[index] = env.nil? ? base.@env[index] : env
      end
      use_env = changes.@use_env
      @use_env = use_env.nil? ? base.@use_env : use_env
    end

    private def set(setting : Setting, value : Int, env : Bool?) : Nil
      if value < 0 || value > setting.maximum
        raise ArgumentError.new("logbuch: #{setting.key} takes 0 to #{setting.maximum}, not #{value}")
      end
      @values[setting.value] = value.to_u32
      @env[setting.value] = env unless env.nil?
    end
  end

  # Changes the settings: the block runs with a `Configuration` as its
  # receiver, and the settings it names change, the others stay. Returns the
  # settings in effect afterwards, which apply to the conversions that start
  # after it returns.
  #
  # ```
  # Logbuch.configure do
  #   max_depth 3
  #   max_cap 50
  # end
  # ```
  #
  # An environment variable that is set to a valid value, such as
  # `LOGBUCH_MAX_DEPTH=8`, overrides the value set in code unless the block
  # switches it off. A value out of range raises `ArgumentError`, and a block
  # that raises changes nothing. A setter called directly in the block with an
  # integer literal out of range, such as `max_depth 300` or `max_cap -1`,
  # fails the build instead.
  #
  # It is a macro, so that a program built with `-Dlogbuch=off` compiles
  # nothing of it. There it only type-checks the block, so a block that does
  # not compile fails that build too, but never runs it, so nothing else the
  # block does happens either; it returns the defaults, as `settings` does,
  # and does not check a value that is not a literal.
  macro configure(&block)
    {% raise "logbuch: Logbuch.configure takes a block, such as Logbuch.configure { max_depth 3 }" unless block %}
    {% maxima = {"max_depth" => ::Logbuch::DEPTH_CEILING, "max_cap" => ::UInt32::MAX, "max_length" => ::UInt32::MAX} %}
    {% for call in (block.body.is_a?(Expressions) ? block.body.expressions : [block.body]) %}
      {% if call.is_a?(Call) && !call.receiver && maxima[call.name.stringify] && !call.args.empty? %}
        {% value = call.args[0] %}
        {% if value.is_a?(NumberLiteral) && ![:f32, :f64].includes?(value.kind) %}
          {% maximum = maxima[call.name.stringify] %}
          {% if value < 0 || value > maximum %}
            {% value.raise "logbuch: #{call.name} takes 0 to #{maximum.to_number}, not #{value.to_number}" %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
    {% if %w[off 0].includes?(flag?(:logbuch)) %}
      typeof(::Logbuch::Configuration.new.__dsl {{ block }})
      ::Logbuch.settings
    {% else %}
      ::Logbuch.__configure(::Logbuch::Configuration.new.__dsl {{ block }})
    {% end %}
  end

  # The settings in effect. The first call reads the environment variables,
  # unless `configure` came first.
  #
  # A program built with `-Dlogbuch=off` gets the defaults, `MAX_DEPTH`,
  # `MAX_CAP` and `MAX_LENGTH`, whatever `configure` sets: it reads no
  # variable and keeps no state.
  def self.settings : Settings
    {% if %w[off 0].includes?(flag?(:logbuch)) %}
      Settings.new(StaticArray(UInt32, SETTING_COUNT).new { |index| Setting.new(index).default })
    {% else %}
      @@settings.get(:acquire) || __first_settings
    {% end %}
  end

  # The state behind `settings` and `configure`, which `-Dlogbuch=off` leaves
  # out, so a program built with it compiles none of it.
  {% unless %w[off 0].includes?(flag?(:logbuch)) %}
    # :nodoc:
    #
    # Where a bad environment variable is reported.
    SETTINGS_LOG = ::Log.for("logbuch")

    # The settings in effect, swapped as a whole so that a reader without a
    # lock never sees a mix of old and new values; nil until first used.
    @@settings = Atomic(Settings?).new(nil)

    # What `configure` has set so far; changed under `@@settings_lock`.
    @@configuration = Configuration.new

    # The environment variables, read once under `@@settings_lock`.
    @@environment : StaticArray(String?, SETTING_COUNT)? = nil

    # The variables already reported as bad, so each is reported once.
    @@reported = StaticArray(Bool, SETTING_COUNT).new(false)

    @@settings_lock = Mutex.new

    # :nodoc:
    #
    # Adds *changes*, which the block of `configure` filled in, to the
    # configuration, and returns the settings in effect afterwards.
    def self.__configure(changes : Configuration) : Settings
      __apply(changes)
    end

    # Reads the variables, unless done, and publishes the first settings, under
    # the lock in case several threads start at once.
    @[NoInline]
    private def self.__first_settings : Settings
      __apply(nil)
    end

    # Adds *changes* to the configuration and publishes the settings it gives.
    # Bad variables are reported after the lock is released, so a log backend
    # that converts values reads the new settings instead of waiting for them,
    # and a backend that raises loses the warning, never the settings.
    private def self.__apply(changes : Configuration?) : Settings
      reports = [] of {Setting, String}
      settings = @@settings_lock.synchronize do
        if changes.nil? && (current = @@settings.get(:acquire))
          next current
        end
        @@configuration = @@configuration.merge(changes) if changes
        resolved = __resolve(@@configuration, reports)
        @@settings.set(resolved, :release)
        resolved
      end
      reports.each { |(setting, text)| __report(setting, text) }
      settings
    end

    # Warns that the variable of *setting* holds *text*, which is not a valid
    # value.
    private def self.__report(setting : Setting, text : String) : Nil
      SETTINGS_LOG.warn &.emit(
        "ignoring #{setting.variable}=#{text.inspect}: it takes a decimal integer from 0 to #{setting.maximum}",
        variable: setting.variable, value: text)
    rescue
    end

    # The settings *configuration* gives: from a variable that is set, valid
    # and switched on, else from code, else the default. Adds the bad variables
    # not reported yet to *reports*.
    private def self.__resolve(configuration : Configuration, reports : Array({Setting, String})) : Settings
      environment = @@environment ||= __read_environment
      values = StaticArray(UInt32, SETTING_COUNT).new do |index|
        setting = Setting.from_value(index)
        from_env = nil
        text = environment[index]
        if text && configuration.env?(setting)
          from_env = __parse(text, setting.maximum)
          if from_env.nil? && !@@reported[index]
            @@reported[index] = true
            reports << {setting, text}
          end
        end
        from_env || configuration.value(setting) || setting.default
      end
      Settings.new(values)
    end

    # The environment variable of each setting, nil where it is unset.
    private def self.__read_environment : StaticArray(String?, SETTING_COUNT)
      StaticArray(String?, SETTING_COUNT).new { |index| ENV[Setting.from_value(index).variable]? }
    end

    # *text* as a value from 0 to *maximum*, or nil if it is anything else:
    # only decimal digits, without a sign or blanks.
    private def self.__parse(text : String, maximum : UInt32) : UInt32?
      return if text.empty? || !text.each_char.all?(&.ascii_number?)
      value = text.to_u32?(whitespace: false)
      value if value && value <= maximum
    end
  {% end %}
end
