require "fiber"
require "log"
require "sync/mutex"

# :nodoc:
class Sync::Mutex
  # :nodoc:
  #
  # Whether the current fiber holds this mutex. A checked or reentrant mutex
  # records the fiber that holds it; an unchecked one records none, so it never
  # counts as held.
  def __logbuch_held? : Bool
    owns_lock?
  end
end

module Logbuch
  # :nodoc:
  #
  # Runs the block under *lock*, the `lock:` of a traced method or a type, and
  # returns its value. A `Sync::Mutex` the current fiber holds already, because
  # the caller took it or an outer conversion did, is not taken again, so the
  # values it protects are logged whatever kind of mutex it is. A nil *lock*,
  # for a type without `lock:` or one whose lock the conversion holds already,
  # only runs the block. The lock may be nil or not at run time, so each
  # overload takes nil too.
  def self.__locked(lock : Sync::Mutex?, &)
    return yield if lock.nil? || lock.__logbuch_held?
    lock.synchronize { yield }
  end

  # :ditto:
  def self.__locked(lock, &)
    return yield if lock.nil?
    lock.synchronize { yield }
  end

  # :nodoc:
  #
  # Runs the block, which converts a trace line's data, under *lock*, the
  # `lock:` of a traced method, as `__locked` does. A lock that raises, when
  # it is taken or released, gives a placeholder naming the exception class
  # instead, so the lock cannot change what the traced method does, as a
  # converter that raises cannot. The block itself rescues what the
  # conversion raises.
  def self.__locked_data(lock, & : -> ::Log::Metadata::Value) : ::Log::Metadata::Value
    __locked(lock) { yield }
  rescue error
    ::Log::Metadata::Value.new("#<lock raised #{error.class}>")
  end
end
