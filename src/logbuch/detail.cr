require "enum"

module Logbuch
  # How much of a value goes into a trace entry, from nothing to everything.
  enum Detail
    # Never logged.
    Omit
    # Identity only: what tells the value apart from others of its type.
    #
    # - An object logs its identity. The same identity stands for the object
    #   in a cycle and past the depth limit, at every detail.
    # - With fields marked `@[LogAs(:id)]`, on the field or on the
    #   `initialize` parameter that sets it, the identity is their values,
    #   each logged at `Id`, so an object in one as its own identity: the one
    #   field's value, such as `"o-17"`, or a hash of them by name, such as
    #   `{"id" => "o-17", "zone" => "eu"}`. They are read under the type's
    #   `lock:`. Where they lead back to an object whose identity is being
    #   logged, that object's id is `…`.
    # - An opted-in class without such a field logs its object id instead,
    #   as in `#<Order:0x10a3f2c40>`.
    # - An opted-in struct without such a field logs only its type, as in
    #   `#<Point>`: anything taken from its fields could give away a
    #   redacted value.
    # - A class or struct that did not opt in logs its `inspect` text, as it
    #   does at every other detail. A collection logs its object id, or for a
    #   set or a slice its type.
    # - Each string of the identity is cut to the length limit, and the text
    #   of one without `:id` fields like `inspect` text.
    # - Strings, numbers, characters, symbols, enums, `Bool`, `Nil` and `Time`
    #   are their own identity and log as at any other detail, a string cut to
    #   the length limit.
    # - So are the value types of the standard library a program has:
    #   `Complex`, `MIME::MediaType`, `Path`, `SemanticVersion`,
    #   `Socket::IPAddress`, `Socket::UNIXAddress`, `Time::Location`,
    #   `Time::Span`, `URI` and `UUID` log their `to_s` text at every detail,
    #   cut to the length limit, and a `URI` its password as `***`.
    # - Collections, tuples and named tuples log each value at `Id`, within
    #   the item limit, and a hash each key too, as it logs its keys at any
    #   detail (see `Hash#to_trace`).
    # - An exception logs its type, message and cause, as at any other detail.
    # - A type with a `to_trace` of its own decides for itself, reading
    #   `Tracer#detail`.
    Id
    # The important parts.
    Summary
    # Everything.
    Full
  end

  # :nodoc:
  #
  # The ways an annotation can write a level, mapped to its name: a symbol
  # such as `:warn`, or a `Log::Severity` path such as `Log::Severity::Warn`,
  # with or without a leading `::`. The macros look up an argument's
  # `stringify`, with the leading `::` of a path removed, so every annotation
  # that takes a level takes the same forms. Read by macros only.
  LEVEL_NAMES = {
    ":trace" => "trace", "Log::Severity::Trace" => "trace",
    ":debug" => "debug", "Log::Severity::Debug" => "debug",
    ":info" => "info", "Log::Severity::Info" => "info",
    ":notice" => "notice", "Log::Severity::Notice" => "notice",
    ":warn" => "warn", "Log::Severity::Warn" => "warn",
    ":error" => "error", "Log::Severity::Error" => "error",
    ":fatal" => "fatal", "Log::Severity::Fatal" => "fatal",
  }

  # :nodoc:
  #
  # The ways an annotation can write a detail, mapped to the name of its
  # `Detail` member: a symbol such as `:full`, or a path such as
  # `Logbuch::Detail::Full`, looked up like `LEVEL_NAMES`.
  DETAIL_NAMES = {
    ":omit" => "Omit", "Logbuch::Detail::Omit" => "Omit",
    ":id" => "Id", "Logbuch::Detail::Id" => "Id",
    ":summary" => "Summary", "Logbuch::Detail::Summary" => "Summary",
    ":full" => "Full", "Logbuch::Detail::Full" => "Full",
  }
end
