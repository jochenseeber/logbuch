require "log"
require "string"

module Logbuch
  # :nodoc:
  #
  # The source *name* names below *parent*, for a `log:` name that starts with
  # a dot: `"shop.checkout"` and `"place"` give `"shop.checkout.place"`.
  def self.__child_source(parent : String, name : String) : String
    parent.empty? ? name : "#{parent}.#{name}"
  end

  # :nodoc:
  #
  # The log a `log:` constant holds.
  def self.__log_value(log : ::Log) : ::Log
    log
  end

  # :ditto:
  def self.__log_value(value : T) : NoReturn forall T
    {% raise "logbuch: log: takes a constant that holds a Log, not a #{T}" %}
  end
end
