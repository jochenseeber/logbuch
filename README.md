# logbuch

[![CI](https://github.com/jochenseeber/logbuch/actions/workflows/ci.yml/badge.svg)](https://github.com/jochenseeber/logbuch/actions/workflows/ci.yml)

Method tracing for [Crystal](https://crystal-lang.org/). Annotate a method, and
logbuch logs each call to it, with the arguments on entry, the result and the
duration on exit, or the exception the method raised.

_Logbuch_ is German for logbook.

The [API documentation](https://jochenseeber.github.io/logbuch/) shows this
README together with the reference of every public type, for the latest
release.

## Overview

Include `Logbuch::Annotations` once, at the top level of your program, and put
`@[Logged]` on each method you want traced:

```crystal
require "logbuch"

include Logbuch::Annotations

module Shop
  class Order
    getter id : String = "o-17"
    getter total : Int32 = 42
    getter items : Array(String) = ["book"]

    @[LogAs(:omit)]
    getter card_number : String = "4111"
  end

  class Checkout
    @[Logged("placing the order")]
    def place(order : Order) : String?
      return nil if order.items.empty?
      "receipt-#{order.id}"
    end

    @[Logged("charging the card")]
    def charge(order : Order) : Nil
      raise ArgumentError.new("card declined")
    end
  end
end

Log.setup(:trace)
checkout = Shop::Checkout.new
checkout.place(Shop::Order.new)
begin
  checkout.charge(Shop::Order.new)
rescue ArgumentError
end
```

Each call writes an entry line and an exit line, or an error line if the method
raises. Here they are as the stdlib's default formatter prints them, without
the timestamps and without the stack trace it adds below the error line:

```text
TRACE - shop.checkout: placing the order -- method: "Shop::Checkout#place", args: {"order" => {"id" => "o-17", "total" => 42}}
TRACE - shop.checkout: done placing the order -- method: "Shop::Checkout#place", result: "receipt-o-17", duration_ns: 625
TRACE - shop.checkout: charging the card -- method: "Shop::Checkout#charge", args: {"order" => {"id" => "o-17", "total" => 42}}
ERROR - shop.checkout: error charging the card -- method: "Shop::Checkout#charge", error: {"type" => "ArgumentError", "message" => "card declined"}, duration_ns: 82209
```

The traced method is written like any other. Its body, signature, return type
and visibility stay as they are, a plain `return` works, and an exception
passes through unchanged.

What logbuch gives you:

- **One annotation per method.** One `include` per program, none per type, and
  no base class. Instance and class methods, private methods, generics, splats,
  blocks and modules all work; see
  [Which methods can be traced](#which-methods-can-be-traced).
- **Structured data.** Arguments, results and errors are `Log::Metadata`, so a
  formatter or backend receives each value separately, nested hashes and arrays
  included. A JSON backend writes them as JSON.
- **Control over what is logged.** Set a detail level per method, and
  `@[LogAs]` per parameter and field: `:omit`, `:id`, `:summary`, `:full` or
  `:redacted`. Converters mask or summarize a value before it is logged.
- **Safe by default.** logbuch caps every value in depth, items and length. It
  logs only types that opt in by their fields, and anything else with
  `inspect`. A log backend that raises loses one line and changes nothing else.
- **Cheap when off.** A call whose level is disabled converts nothing and costs
  a few nanoseconds, without allocating. `-Dlogbuch=off` compiles tracing out.
- **Plain stdlib `Log`.** Levels, sources, formatters and backends work as they
  do for your own log lines, and so does `LOG_LEVEL` once the program calls
  `Log.setup_from_env`.

The [examples](examples/) directory has runnable programs for the main
features, one per area; `rake examples` runs them all.

## Installation

Add the dependency to your `shard.yml` and run `shards install`:

```yaml
dependencies:
  logbuch:
    github: jochenseeber/logbuch
```

logbuch needs Crystal 1.21 or later, and `shards` on the `PATH` when your
program compiles, since it reads `Logbuch::VERSION` with `shards version`.

logbuch assumes nothing about the prelude: it requires the parts of the
standard library it uses itself, such as `log`, `array`, `hash`, `mutex` and
`time`, and defines nothing for the others. A program built with a prelude of
its own, such as `--prelude=empty` and the requires it picks, needs only what
`log` and the start of a program need; `spec/support/own_prelude.cr` lists the
fewest files of the standard prelude that do. A collection or value type
logbuch logs but does not use, such as `Deque`, `Set`, `URI` or `UUID`, gets
its conversion only if the program has it, whatever the order of its requires.

## Usage

### Annotations

The annotations are defined in `Logbuch::Annotations`. Include that module
once, at the top level of your program, and write them without a prefix in
every file:

```crystal
require "logbuch"

include Logbuch::Annotations
```

| Annotation     | Goes on                | Sets                                                                  |
| -------------- | ---------------------- | --------------------------------------------------------------------- |
| `@[Logged]`    | a method               | that the method is traced, its description, level, detail and options |
| `@[LogError]`  | a method, tracing it   | the level and stack trace of the error lines for some exceptions      |
| `@[LogAccept]` | a method, tracing it   | exceptions logged as the result instead of as an error                |
| `@[LogAs]`     | a parameter or a field | its detail, or that it is redacted, and its converter and limits      |
| `@[LogType]`   | a type                 | that it is logged by its fields, its lock, log and stack trace        |

```crystal
class Checkout
  @[Logged("placing the order", :debug)]
  def place(order : Order, @[LogAs(:redacted)] coupon : String) : Receipt
  end
end
```

Wherever an annotation takes a level, in `@[Logged]`, its `slow:` option,
`@[LogError]` or `@[LogAccept]`, the level is a symbol, `:trace` to `:fatal`,
or the `Log::Severity` member, such as `Log::Severity::Warn`, with or without a
leading `::`. Wherever it takes a detail, in `@[Logged]` or `@[LogAs]`, the
detail is a symbol, `:omit` to `:full`, or the `Logbuch::Detail` member, such
as `Logbuch::Detail::Full`.

`@[LogError]` and `@[LogAccept]` trace a method on their own, as a `@[Logged]`
without arguments does, so `@[Logged]` is needed only for its description,
level, detail or options.

logbuch includes `Logbuch::Tracing`, which traces the methods, into each type
with a traced method. A private type, or a type inside one, is the exception:
logbuch cannot reopen it from outside its file, so the build fails until the
type includes `Logbuch::Annotations`, which includes `Logbuch::Tracing` into
it:

```crystal
private class Ledger
  include Logbuch::Annotations

  @[Logged]
  def total(amounts : Array(Int32)) : Int32
    amounts.sum
  end
end
```

logbuch adds no names to your program by itself; the short names exist only
where you include the module. Without the top-level include, write the full
names, such as `@[Logbuch::Annotations::Logged]`, or include the module into
each type that uses them. A shard that uses logbuch should do one of these, not
include the module at the top level, so it works in any program.

If your program has its own `Logged`, `LogAs`, `LogError`, `LogAccept` or
`LogType`, skip the top-level include and write logbuch's annotations by their
full names, or give them names of your own with an alias:

```crystal
class LogError < Exception # your own exception
end

alias Traced = Logbuch::Annotations::Logged

class Shop
  @[Traced]
  @[Logbuch::Annotations::LogError(IO::Error, :warn)]
  def place : Nil
  end
end
```

### What gets logged

The description in `@[Logged]`, such as `"placing the order"`, is the message,
as written. Without one, the message is the method name with a marker:

| Line  | With a description        | Without                 | Data                                                                                                       |
| ----- | ------------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------- |
| entry | `placing the order`       | `>Shop::Checkout#place` | `method`, `args` with one key per argument                                                                 |
| exit  | `done placing the order`  | `<Shop::Checkout#place` | `method`, `result` (not for `Nil` or `Void` methods), `duration_ns`, `slow` (only `true`, for a slow call) |
| error | `error placing the order` | `!Shop::Checkout#place` | `method`, `error` with `type`, `message` and `cause`, `duration_ns`                                        |

Instance methods are named `Type#method`, class methods `Type.method`. A method
without logged arguments has no `args` key. If the caller's block leaves a
traced method that yields with `break` or `return`, logbuch still writes the
exit line, without `result`.

`Logbuch::Keys` names the keys as constants for code that reads the lines:
`METHOD`, `ARGS`, `RESULT`, `ERROR`, `DURATION` and `SLOW`, which are symbols
like the keys of `Log::Entry#data`, and `TYPE`, `MESSAGE` and `CAUSE` inside
`error`. To build the messages differently, see [Messages](#messages).

### Detail levels

A detail symbol in `@[Logged]` sets how much of the arguments and the result
goes into the log: `:omit`, `:id`, `:summary` (the default) or `:full`, or a
`Logbuch::Detail` value such as `Logbuch::Detail::Full`, as in
`@[Logged("placing the order", :full)]`. With `:omit`, the lines carry no
result and no arguments, except a parameter that sets its own detail with
`@[LogAs]`.

Parameters and fields carry one `@[LogAs]` each:

| Annotation                 | On a parameter                           | On a field                                     |
| -------------------------- | ---------------------------------------- | ---------------------------------------------- |
| `@[LogAs(:omit)]`          | never logged                             | never logged                                   |
| `@[LogAs(:id)]`            | logged at `Id` detail                    | logged at `Id` and above                       |
| `@[LogAs(:summary)]`       | logged at `Summary` detail               | logged at `Summary` and up                     |
| `@[LogAs(:full)]`          | logged at `Full` detail                  | logged only at `Full`                          |
| `@[LogAs(:redacted)]`      | logged as `"***"` at the method's detail | logged as `"***"` where it would be without it |
| `@[LogAs(:id, :redacted)]` | logged as `"***"` at `Id` detail         | logged as `"***"` at `Id` and above            |

`:redacted` goes with any detail but `:omit`, in either order; the detail then
sets where the value is logged, and it is always logged as `"***"`. It takes no
`converter:`; a converter that masks a value goes without it. A parameter
without an annotation uses the method's detail. Use `@[LogAs(:omit)]` to keep a
secret argument out of the log:

```crystal
@[Logged]
def pay(order : Order, @[LogAs(:omit)] card_number : String) : Bool
```

`items(...)` sets how each item of a collection is logged, apart from the
collection: its detail, `:id`, `:summary` or `:full`, and the options `cap:`,
`length:` and `converter:`, which apply to each item as they would to the
collection (see [Limits](#limits)). It applies to the items of an array, deque,
set or slice, the elements of a tuple and the values of a hash or named tuple,
and everything inside an item follows its detail, as a detail passes down. The
detail may be higher or lower than the one the collection is logged at. `cap:`
and `converter:` next to it apply to the collection itself, and `items(...)`
applies to what that converter returns. Crystal takes positional arguments
before named ones, so `items(...)` goes before them. It fails the build on
anything but such a collection. Hash keys are logged at `Id` anyway (see
[Limits](#limits)), and inside an identity, where every value is logged at
`Id`, it has no effect:

```crystal
@[LogType]
class Customer
  @[LogAs(:summary, items(:id))]
  getter orders : Array(Order) # "orders" => ["o-17", "o-18"]

  @[LogAs(:summary, items(length: 20, converter: ->(note : String) { note.strip }), cap: 5)]
  getter notes : Array(String)
end

@[Logged(:id)]
def ship(@[LogAs(items(:full))] orders : Array(Order)) : Nil
```

Field annotations go on the instance variable, on the `getter` or `property`
that declares it, or on an `initialize` parameter that sets it, such as
`def initialize(@[LogAs(:omit)] @token : String)`. `@[Logged]` goes on methods
only, and `@[LogAs]` only on parameters and fields; mixing them up on a method
or parameter fails the build. A `@[Logged]` on a field does nothing: Crystal
copies a method's annotations onto the instance variables it assigns, so
logbuch cannot tell a misplaced one from a copied one.

logbuch logs a class or struct by its fields only when it opts in. A type opts
in when it or a parent class carries `@[LogType]`, has a traced method,
includes `Logbuch::Tracing` (through `Logbuch::Annotations`, a parent class or
a module too), or has a `@[LogAs]` on one of its fields or `initialize`
parameters, its own or a parent class's. logbuch logs any other object with
`inspect`, unless its type defines `to_trace`. So stdlib and shard objects such
as a `Mutex` or an `IO` show up as their `inspect` text, and logbuch never
walks their internals. The stdlib value types such as `UUID` and `Path` log
their text instead, as described for `Id` below.

```crystal
@[LogType]
class Order
  getter id : String
  getter items : Array(String)
end
```

In a type that opted in, a field without an annotation shows at `Summary` if
its type is a string or a value type (numbers, `Bool`, `Nil`, `Symbol`, enums
and structs other than `Set`), and only at `Full` otherwise. So at `Summary`,
an object shows its strings and numbers but not the objects and collections it
holds.

At `Id`, a value shows only what tells it apart from others of its type, its
identity:

| Value                                  | At `Id`                                          |
| -------------------------------------- | ------------------------------------------------ |
| object with an `@[LogAs(:id)]` field   | that field's value: `"o-17"`                     |
| object with several such fields        | them by name: `{"id" => "o-17", "zone" => "eu"}` |
| other opted-in class                   | its object id: `"#<Order:0x10a3f2c40>"`          |
| other opted-in struct                  | its type only: `"#<Point>"`                      |
| class or struct not opted in           | its `inspect` text: `"Point(@x=1, @y=2)"`        |
| string, number, symbol, enum, and such | itself, a string cut to the length limit         |
| `UUID`, `Path` and other value types   | its text: `"/srv"` for `Path["/srv"]`            |
| array, hash, tuple and other container | its values and keys at `Id`: `["o-1"]`           |
| exception                              | type, message and cause, as at any other detail  |

Each `:id` field is logged at `Id`, so an object in one logs its own identity:
a `Ticket` with the `:id` fields `number` and `order` as
`{"number" => "t-1", "order" => "o-17"}`. The fields are read under the type's
`lock:`. Where they lead back to an object whose identity is being logged, that
object's id is `…`: two `Peer`s whose `:id` fields name each other log as `…`,
since no value ends the chain. Each string of an identity is cut to the length
limit, and the text of one without `:id` fields too, like `inspect` text. A
type name in it is the full name without type arguments: `#<Box:0x…>` for a
`Box(Int32)`.

A struct has no object id, so an opted-in one without `:id` fields logs only
its type, as in `#<Point>`, and two such structs look the same. Anything taken
from its fields, such as a hash, could give away a redacted value, even one
inside a nested struct. Mark a field `:id` to tell structs apart.

A class or struct that did not opt in is logged with `inspect` at every other
detail, so at `Id` it logs that too, cut to the length limit: its `inspect`
shows nothing it would not show anyway. A collection, such as an array or a
set, converts its items instead, and logs as an identity with its object id or,
for a set or a slice, its type.

So `:id` never logs the `inspect` text of an opted-in object, and it neither
reads the fields of a class without `@[LogAs(:id)]` fields nor takes its
`lock:`. The same identity stands for an object in a cycle and past the depth
limit, at every detail (see [Limits](#limits)). A type with its own `to_trace`
decides for itself how it logs at `Id`; `Logbuch::Tracer#detail` tells it the
detail.

The value types of the standard library whose value is their identity log their
`to_s` text at every detail, cut to the length limit: `Complex`,
`MIME::MediaType`, `Path`, `SemanticVersion`, `Socket::IPAddress`,
`Socket::UNIXAddress`, `Time::Location`, `Time::Span`, `URI` and `UUID`. So
`Path["/srv"]` logs as `"/srv"` and `1.second` as `"00:00:01"`, and a URI logs
its password as `***`. logbuch gives a `to_trace` only to those types the
program has, whatever the order of its requires, and keeps one the program gave
such a type itself. `BigInt`, `BigFloat`, `BigDecimal` and `BigRational` are
numbers and log their text as well.

A value type of the program logs its value at every detail the same way, with a
`to_trace` of its own that converts its text, cut to the length limit the value
has:

```crystal
struct Sku
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    tracer.convert(to_s, length: tracer.length)
  end
end
```

### Converters

`@[LogAs]` on a parameter or field can take a converter, a block in arrow
notation with one parameter. Its return value is logged instead, at the
annotation's detail, so a converter can mask a value partly. `:redacted` always
logs `"***"`, so it takes no converter, and the two together fail the build:

```crystal
@[Logged]
def pay(
  order : Order,
  @[LogAs(converter: ->(number : String) { "****#{number[-4..]}" })] card_number : String,
  @[LogAs(:summary, converter: ->(code) { code.upcase })] voucher : String,
) : Bool
```

This logs `"card_number" => "****4444"` under `args`, and the voucher code in
upper case. The parameter type is optional. If a converter raises, the call
still runs and the log shows `#<convert raised ArgumentError>`.
`@[LogAs(:omit)]` takes no converter, since that value is never logged.

The `result:` option of `@[Logged]` is a converter for the result:

```crystal
@[Logged(result: ->(rows) { rows.size })]
def query(sql : String) : Array(Row)
```

This logs the number of rows instead of the rows. A method that logs no result,
because it returns `Nil` or has the detail `:omit`, cannot take one.

To control how a type appears in the log wherever it is logged, define
`to_trace` on it. It receives a `Logbuch::Tracer`, which carries the detail and
the limits, and converts the values inside with `tracer.convert`, so cycles and
the depth limit are handled for them:

```crystal
struct Money
  def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
    Log::Metadata::Value.new({"amount" => tracer.convert(@cents / 100), "currency" => tracer.convert(@currency)})
  end
end
```

`tracer.detail` is the detail the value is logged at, `tracer.cap` and
`tracer.length` are its item and length limits, and
`tracer.convert(value, cap:, length:)` sets limits of its own for one value.
The limits are `UInt32`, so a literal such as `cap: 10` fits as it is and an
`Int32` variable needs `.to_u32`.

With a block, `tracer.convert` converts what the block returns for the value,
the way a `converter:` on `@[LogAs]` does, and takes the same limits:

```crystal
def to_trace(tracer : Logbuch::Tracer) : Log::Metadata::Value
  Log::Metadata::Value.new({"card" => tracer.convert(@card_number) { |number| "****#{number[-4..]}" }})
end
```

If the block raises, the value is logged as `#<convert raised IndexError>`, and
if converting what it returns raises, as `#<to_trace raised IndexError>`; the
rest of the value is logged as usual.

A `Logbuch.convert` inside `to_trace` is safe too: it nests in the conversion
under way, so a value that converts itself again stops at the cycle, and
nothing nests deeper than 256 levels. It starts with its own detail and the
default limits, though, so `tracer.convert` is the one to use for the values
inside.

`Logbuch.convert(value, detail: :full)` converts a value the way a traced
method logs it, for use in tests; `detail:` defaults to `:summary`.

### What reaches the log

logbuch hides what the annotations mark, and the password of a `URI`, and
nothing else. Four things reach the log as they are, and keeping secrets out of
them is up to the application:

- Exception messages. Error lines, and the results of accepted exceptions, log
  the message whole, also for a method with the detail `:omit`. A message that
  includes an argument, such as `"invalid card #{number}"`, logs that argument.
- `inspect` text. A type that did not opt in is logged with `inspect`, which
  shows every field it holds. An opted-in object inside it masks itself (see
  [Inspect](#inspect)), but a type with an `inspect` of its own shows what that
  writes. That covers stdlib types such as `HTTP::Headers`, with its
  `Authorization` header. Opt the type in, give it a `to_trace`, or mark the
  parameter or field with a converter, `:redacted` or `:omit`.
- The text of the stdlib value types, such as a `URI` with a token in its
  query.
- Whatever a converter returns.

Converters, `to_trace` and `inspect` run on every call whose level is enabled,
so keep them cheap and free of side effects.

### Inspect

logbuch writes the `inspect` of every type that opted in, unless the type or an
ancestor writes its own. It keeps Crystal's form but shows only the fields
shown at `:summary`, by the same rules as the log, so `:redacted` ones as
`"***"`, converted ones as their converter's result, and `:omit` ones never. It
reads them under the type's `lock:`. So `p`, `pp`, string interpolation, a
struct's `to_s`, and the `inspect` of a type that did not opt in and holds such
an object, show no secret either:

```crystal
p PaymentCard.new("Ada Lovelace", "4111222233334444")
# #<PaymentCard:0x10a3f2c40 @holder="Ada Lovelace", @number="****4444">
```

`@[LogType(inspect: :full)]` shows the fields shown at `:full` instead, `:id`
only the `:id` fields, and `:off` keeps Crystal's `inspect`. A subclass takes
the setting of its nearest ancestor that has one. Any other value, or
`inspect:` on a type with an `inspect` of its own, fails the build. The
`inspect` is the same with `-Dlogbuch=off`: hiding a secret does not depend on
logging.

### Exceptions

logbuch writes an error line whatever the method's level, so an error shows
even when the method's own lines are filtered out; then it has no
`duration_ns`. The line is at `:error`, unless a `@[LogError]` of the method
names another level; see
[Error levels and stack traces](#error-levels-and-stack-traces). The call where
an exception first appears logs it in full and attaches it to the log entry
(`Log::Entry#exception`), so a formatter or error backend can report its stack
trace. Each traced call the exception passes through after that writes an error
line with only its type. An exception object is logged in full only once in its
lifetime. Raised again later, such as one kept in a constant, it gets error
lines with only its type.

To log an error, a traced method catches the exception and raises it again,
also when its own lines are filtered out. That roughly doubles the cost of an
exception raised through one traced method, and each further traced method it
passes adds about as much again (measured in a release build at 29 µs against
13 µs for one frame, and 49 µs against 16 µs for two). This matters only for
code that raises in normal operation.

### Accepted exceptions

Some exceptions are an expected outcome, such as a lookup that raises
`KeyError` for a missing key. List them in `@[LogAccept]` to log them as the
result instead of as an error:

```crystal
@[Logged("finding a user")]
@[LogAccept(KeyError, IO::TimeoutError)]
def find(id : String) : User
```

When `find` raises one of these exceptions or a subclass of one, the call
writes its exit line, `done finding a user`, with the exception under `result`.
The `result` holds the same `type`, `message` and `cause` that an error line
shows, also for `Nil` and `Void` methods and with the detail `:omit`. Any other
exception writes an error line. Either way, the method raises the exception
again.

The exit line is at the method's level, or at the level the annotation names,
such as `@[LogAccept(KeyError, :info)]`; a slow call still gets the `slow:`
level when that is higher. It carries no stack trace unless the annotation has
`stacktrace: true`, which attaches the exception to the exit line. A method can
carry several `@[LogAccept]`, one per level or setting, and the most specific
type wins.

An accepted exception's exit line logs it in full, like an error line, so a
traced caller that does not accept it writes an error line with only its type.
If the exit line is not written, because its level is disabled, the caller's
error line logs it in full instead.

### Error levels and stack traces

The error line where an exception first appears has the exception attached, and
the stdlib formatters print it with its stack trace. For an exception that is
an expected failure, such as a validation error, the stack trace adds nothing
to its type and message. `stacktrace: false` in the `@[LogType]` of the
exception class leaves it out wherever the exception is logged:

```crystal
@[LogType(stacktrace: false)]
class OutOfStock < Exception
end
```

logbuch still writes the error line, with the same message and the same `error`
data; it only leaves the exception off, so a formatter prints no stack trace
and an error backend that reads `Log::Entry#exception` gets `nil`. Subclasses
inherit the setting, and a subclass can set `stacktrace: true` to get its stack
trace back.

A traced method can decide for itself with `@[LogError]`, which takes exception
types, a level and `stacktrace:`. The level, such as `:warn` or
`Log::Severity::Warn`, defaults to `:error`, and `stacktrace:` to what the
exception type says:

```crystal
@[Logged("syncing the stock")]
@[LogError(IO::Error, :warn, stacktrace: false)]
@[LogError(IO::TimeoutError, OutOfStock, stacktrace: true)]
def sync : Nil
```

Each annotation applies to its types and their subclasses, and the most
specific type wins, whatever the order. Here an `IO::TimeoutError` keeps its
stack trace and is logged at `:error`, and any other `IO::Error` loses it and
is logged at `:warn`. A `@[LogError]` without types, such as
`@[LogError(:warn)]`, applies to every exception the method's other
`@[LogError]` annotations do not list. A type can be listed only once among a
method's `@[LogError]` and `@[LogAccept]` annotations. The traced call where
the exception first appears decides about the stack trace; the calls it passes
through after that log only its type, as always, each at the level its own
`@[LogError]` sets.

### Log level, source and timing

```crystal
@[Logged("loading a checkout", :debug, log: ".load", timing: false)]
def self.load(path : String) : Checkout
```

- The level, `:trace` to `:fatal`, sets the severity of a call's entry and exit
  lines; error lines are written at `:error` or at their `@[LogError]` level.
  It defaults to `:trace` and can also be a `Log::Severity` value such as
  `Log::Severity::Debug`. The description, the level and the detail can come in
  any order, since logbuch tells them apart by what they are. `:trace` is below
  the stdlib's default of `:info` and below `:debug`, so lines at the default
  level show only with `Log.setup(:trace)`, or with `LOG_LEVEL=TRACE` once the
  program calls `Log.setup_from_env`; `LOG_LEVEL=DEBUG` shows none of them.
- `timing:` turns `duration_ns` on or off; it is on by default, in debug and
  release builds alike. `duration_ns` is the call's duration in whole
  nanoseconds, a `UInt64`. It covers the method itself, not writing the lines
  or converting the arguments and the result. logbuch reads the clock only when
  it can write one of the call's lines, which needs the method's level or its
  `slow:` level enabled.
- `log:` sends the lines to another log, see below.

A traced method logs to whatever `Log` means inside its type, the same `Log`
your own `Log.info` calls use. That can be a constant in the type, in an
enclosing module or in a parent class. If none is defined, the source comes
from the type name, so `Shop::Checkout` logs under `shop.checkout`. At run
time, `Log.setup`, and `LOG_LEVEL` once the program calls `Log.setup_from_env`,
apply as they do to your own log lines. When a method's level is disabled for
its source, its arguments are not converted, and no clock is read unless its
`slow:` level is enabled.

`log:` names another log, for one method on `@[Logged]` or for a whole type on
`@[LogType]`. It takes a source name, a name below the type's log when it
starts with a dot, or a constant that holds a `Log`:

```crystal
AUDIT_LOG = Log.for("audit")

module Shop
  Log = ::Log.for("shop")

  class Checkout
    # Logs under "shop.place", so Log.setup("shop.place", :trace) turns on
    # this method alone.
    @[Logged(log: ".place")]
    def place(order : Order) : Receipt
    end

    @[Logged(log: AUDIT_LOG)]
    def refund(order : Order) : Bool
    end
  end

  # Every traced method of the type and its subclasses logs under "payments".
  @[LogType(log: "payments")]
  class Payments
  end
end
```

A name with a dot on `@[LogType]` is below the log the type would have without
it, and a subclass resolves it below its own. Each log is resolved once, so
`log:` costs nothing per call.

### Slow calls

`slow:` writes the exit line of a slow call at a higher level, so a level
filter that hides the method's other calls still shows the slow ones:

```crystal
@[Logged(slow: {ms: 200, level: :warn})]
def search(query : String) : Array(Result)
```

Every call still writes its entry and exit lines. A call of 200 ms or more
writes its exit line at `:warn`, with `slow: true` after the other data, so a
backend can pick slow calls out without knowing their thresholds; the exit line
of any other call has no `slow` key. The `level:` of `slow:` defaults to
`:warn` and must be above the method's own level, or the build fails. Each line
checks its own level before it converts anything. With the stdlib's default
level of `:info`, only the slow calls of this `:trace` method show up, and the
other calls convert neither their arguments nor their result. `slow:` needs
timing, so it cannot be combined with `timing: false`, and with
`-Dlogbuch_timing=off` no call counts as slow.

A slow call whose entry line is disabled logs no arguments, since they are only
converted for the entry line. With `args: true`, its exit line carries them as
well:

```crystal
@[Logged(slow: {ms: 200, args: true})]
def search(query : String) : Array(Result)
```

These arguments are converted after the method returns, so they show what the
values are then, and only a slow call pays for converting them.

### Limits

logbuch caps every traced value, so a large or deep argument cannot stall or
crash the program:

| Setting      | Default          | Beyond it                                         |
| ------------ | ---------------- | ------------------------------------------------- |
| `max_depth`  | 16 nested levels | the value is logged as its identity               |
| `max_cap`    | 100 items        | the rest of a collection is counted: `… 900 more` |
| `max_length` | 1,024 characters | the rest is counted in bytes: `… (+3976 bytes)`   |

The defaults are the constants `Logbuch::MAX_DEPTH`, `Logbuch::MAX_CAP` and
`Logbuch::MAX_LENGTH`; [Settings](#settings) change them at run time.

A value that can hold other values takes a level: an object of a class, an
array, deque, set, slice, hash, tuple or named tuple, and a struct logged by
its fields or with `inspect`. Past the depth limit, such a value is logged as
its identity (see [Detail levels](#detail-levels)), such as `"o-17"` or
`#<Point>`; a tuple, named tuple, set or slice, which are structs too, as its
type, such as `#<Tuple>`. A value that holds no other values takes no level and
is logged by value at any depth: a string, number, `Bool`, `Nil`, character,
symbol, enum or `Time`, a stdlib value type such as `UUID`, `Path` or `URI`,
and a struct with a `to_trace` of its own, whose converted values take their
own levels. An object with a `to_trace` of its own still takes a level: unlike
a struct, it can contain itself, so a list of such objects stops at the depth
limit.

Each key of a hash is converted first, at `:id`, whatever the hash's detail: a
key tells its entry apart from the others, as an identity does (see
[Detail levels](#detail-levels)). A string key is cut as a string value is, a
symbol is logged as its text and a number as itself. An object or struct with
`:id` fields is logged by them: with one, as that field's value, so an
`Account` with an `:id` field `id` as `a1`; with several, as a hash of them by
name, so a `Seat` as `{"row" => 12, "letter" => "A"}`. An object or struct in
an `:id` field follows the same rule. An opted-in class without `:id` fields is
logged as its object id, such as `#<Session:0x10a3f2c40>`, and an opted-in
struct as its type, such as `#<Badge>`, so a key never shows their fields. Any
other key logs as it does at `:id` as a value: `Path["/srv"]` as `/srv`, `'a'`
as `'a'`, a struct that did not opt in as its `inspect` text, such as
`Point(@x=0, @y=0)`, and an array its items at `:id`. Cycles and the depth
limit hold for a key too, and a key is never logged by its `to_s`.

A hash is logged as an array of key and value pairs, each key as it converts,
so keys of any type, and keys that convert to the same value, such as two
structs logged as `#<Badge>`, keep their entries:

```crystal
[["a1", "admin"], [{"row" => 12, "letter" => "A"}, "window"]]
```

A hash counts the rest as a last item, as an array does: `"… 900 more"`. A
named tuple, whose keys are names, is logged as a hash: `{"id" => 7}`.

The length limit also cuts hash keys, exception messages, the text of the
stdlib value types, identities and the `inspect` text of objects that did not
opt in. `inspect` stops writing when it reaches the limit, so a large or deeply
nested object costs no more than the text that is logged. Such text ends in `…`
without a count, since the rest was never written. A key is cut by the length
limit of the hash: a string with a count, as any string, and an identity or
`inspect` text like other such text.

`@[LogAs]` on a field or parameter can set its own item and length limits. Each
applies to the annotated value, or to what its `converter:` returns:

- `cap:` limits the items of the annotated array, deque, set, slice or hash
  itself.
- `length:` cuts the annotated string itself, the keys of the annotated hash,
  an exception's message, the text of a stdlib value type such as `UUID`, the
  `inspect` text of an object that did not opt in, or the identity of an object
  logged at `:id`.

How deep a value nests is the `max_depth` setting only; an annotation cannot
change it.

`cap:` and `length:` do not reach the values inside the annotated one: its
strings and nested collections get the settings again, so `length:` on an
`Array(String)` would cut nothing. `items(...)` sets them for the items of a
collection instead (see [Detail levels](#detail-levels)):
`@[LogAs(items(length: 80))]` cuts each string of an `Array(String)`, and
`@[LogAs(items(cap: 5), cap: 10)]` logs ten lists of an `Array(Array(Int32))`
at most, each with five numbers at most. An option that cannot change how the
value or its items are logged fails the build: `cap:` on a type that is not one
of those collections, and `length:` on a type it cannot cut, such as a number,
a character, `Bool`, a symbol, an enum, an array, a tuple or an object logged
by its fields; in `items(...)`, against the type of the items, unless it has a
converter of its own. A union, a parameter without a type, a parameter of a
method that is not traced, and a type with its own `to_trace` are not checked.
An option that is left out means the setting applies.

At `:id`, every object is logged as its identity, such as `"o-17"` (see
[Detail levels](#detail-levels)), which is the same at any depth. So on a
parameter logged at `:id`, by its own `@[LogAs]` or by the method's
`@[Logged(:id)]`, `length:` cuts the identity, each string of it, also of an
object logged by its fields. Strings, the stdlib value types, exceptions and
collections are logged as at any other detail and keep their limits there. A
field's detail only sets from which detail of the object around it the field is
shown, and its value is logged at that object's detail, so
`@[LogAs(:id, length: 80)]` on a field cuts its `inspect` text at `:summary`
and its identity at `:id`, and passes the check on an object logged by its
fields too.

```crystal
class Report
  @[LogAs(:summary, items(length: 20), cap: 10)]
  getter tags : Array(String)

  @[LogAs(:summary, length: 80)]
  getter title : String
end
```

The options take non-negative integers. With `:omit`, the value is never
logged, and with `:redacted`, the value itself is not, so an option there fails
the build.

Tuples and named tuples have a size fixed in the code, so the item limit does
not apply to them and they are logged whole. Their elements still follow the
limits.

logbuch logs an object that contains itself, directly or through other objects,
as its identity where it repeats, as it logs an object past the depth limit: a
`Node` with an `:id` field `name` as `"a"`, a class without `:id` fields as
`#<Node:0x10a3f2c40>`. A struct cannot contain itself, but past the depth limit
it is logged as its identity too, as `#<Point>`. So the object that is cut off
reads the same as wherever else it appears:

```crystal
{"name" => "a", "next_node" => {"name" => "b", "next_node" => "a"}}
```

### Settings

The limits are settings, which `Logbuch.configure` changes at run time:

```crystal
Logbuch.configure do
  max_depth 3
  max_cap 50
end
```

`max_depth` takes 0 to 256 (`Logbuch::DEPTH_CEILING`); `max_cap` and
`max_length` take 0 to `UInt32::MAX`. They take any integer type, such as an
`Int32` variable. A value out of range, a negative one included, raises
`ArgumentError`, and then no setting changes. Each call changes the settings
its block names and keeps the others. The new settings apply to the values
converted after `configure` returns; a conversion already running finishes with
the settings it started with. `configure` returns the settings in effect
afterwards, and `Logbuch.settings` returns them at any time.

`configure` is a macro, so that it compiles to nothing with
[`-Dlogbuch=off`](#build-flags). Called directly in its block with an integer
literal out of range, such as `max_depth 300` or `max_cap -1`, a setter fails
the build instead of raising, with tracing on or off.

Whoever runs the program can override a setting with an environment variable,
without rebuilding it:

```sh
LOGBUCH_MAX_DEPTH=4 LOGBUCH_MAX_LENGTH=200 ./shop
```

`LOGBUCH_MAX_DEPTH`, `LOGBUCH_MAX_CAP` and `LOGBUCH_MAX_LENGTH` hold a decimal
integer in the setting's range. They are read once, when the settings are first
used, and a valid value wins over the code, even over a `configure` that runs
later. Any other value is ignored with one warning on the `logbuch` source; a
bad variable never raises.

The code can switch the variables off: all of them with `use_env false` in
`configure`, or one with `env: false` on its setter, such as
`max_length 256, env: false`. That also drops a value already taken from the
variable. `use_env true`, or `env: true` on a setter, switches it on again.

### Messages

Three macros in `Logbuch::Messages` build the messages: `entry_message`,
`exit_message` and `error_message`. Each takes `call`, a named tuple literal of
what is known about the traced method when the program compiles, and expands to
the message, a `String`:

| Key            | Example                        | Notes                                 |
| -------------- | ------------------------------ | ------------------------------------- |
| `type`         | `"Shop::Checkout"`             | without generic arguments             |
| `method`       | `"place"`                      |                                       |
| `class_method` | `false`                        |                                       |
| `label`        | `"Shop::Checkout#place"`       | the `method` value of the line's data |
| `description`  | `"placing the order"` or `nil` | the annotation's string, as written   |
| `level`        | `"trace"`                      | the method's level                    |
| `params`       | `["order", "coupon"]`          | the parameters' internal names        |

`params` lists the parameters in order by their internal names, the names the
`args` data uses: `def place(order, using coupon)` gives `["order", "coupon"]`.
A splat or double splat appears under its bare name, and so do parameters
marked `:omit` or `:redacted`; an unnamed `*` and the block parameter are left
out.

To build the messages differently, reopen the module after requiring logbuch
and define the converters you want to replace:

```crystal
module Logbuch::Messages
  macro entry_message(call)
    {{ "→ #{call[:label].id}" }}
  end

  macro exit_message(call)
    {{ "← #{call[:label].id}" }}
  end
end
```

`Shop::Checkout#place` then writes `→ Shop::Checkout#place` and
`← Shop::Checkout#place`, with or without a description; its error line keeps
the default message. The last definition wins, wherever it is, and one set of
converters serves the whole program.

Each message is kept in a constant of the traced type, so a converter cannot
refer to the call's arguments or result. A message that expands to a string
literal, as the defaults do, costs nothing per call; a computed one, such as
`{{ call[:label] }}.upcase`, is computed once. An expansion that is not a
`String` fails the build at the traced method, whether or not the method is
called. With `-Dlogbuch=off`, no wrappers are generated, so no message is
computed, but the converters are still expanded and checked.

### Fibers and threads

Lines carry no fiber name. To tell the lines of concurrent calls apart, set it
in the log context when a fiber starts; every line written in that fiber,
logbuch's and your own, then carries it:

```crystal
spawn(name: "worker-1") do
  Log.context.set(fiber: Fiber.current.name)
  # ...
end
```

logbuch reads arguments, results and fields without taking any lock. In a
program that runs fibers in parallel, for example in a
`Fiber::ExecutionContext::Parallel`, a collection that another thread changes
while it is being logged can crash the program. This happens even when the
writers hold a lock, because the trace does not take it. `Array#clear`, for
example, zeroes the slots a reader may still be reading.

Log such a value under the lock its writers take, with `lock:`. On a type,
`@[LogType(lock: @lock)]` converts its fields while holding the lock, so the
type is safe wherever it is logged. The field that holds the lock is logged
like any other field, from `:full`; mark it `@[LogAs(:omit)]` to leave it out:

```crystal
@[LogType(lock: @lock)]
class JobQueue
  @lock = Sync::Mutex.new
  @jobs = [] of Job
end
```

On a method, `@[Logged(lock: @lock)]` holds the lock while it converts the
arguments for the entry line and the result for the exit line, but not while
the method runs. Converters run under the lock too:

```crystal
@[Logged(lock: @lock)]
def audit(jobs : Array(Job)) : Nil

@[Logged(lock: @lock, result: ->(jobs) { jobs.size })]
def pending : Array(Job)
```

`lock:` takes an instance or class variable, a method call or a constant.
logbuch does not take a `Sync::Mutex` that the current fiber holds already,
whether the caller took it or a conversion further out did. So a traced call
made under the lock logs as usual, whether the mutex is checked, reentrant or
not. An unchecked mutex does not record who holds it; it deadlocks instead. Any
other lock is taken with its `synchronize` method. A lock that raises when a
traced method's line takes it, such as one that refuses to be taken twice,
leaves `#<lock raised Exception>` in place of the line's arguments or result,
and the method runs and returns as without tracing. A value without a lock to
take is best left out with `@[LogAs(:omit)]`; `@[LogAs(:id)]` still reads every
item of a collection.

### Build flags

- `-Dlogbuch=off` compiles all tracing out. Annotated methods become plain
  methods, and a program that does not call `Logbuch.convert` itself compiles
  no code of logbuch: its binary holds no more of it than the names of its
  types, such as `Logbuch::Detail`, which the compiler keeps for every type,
  and Crystal's `Log`, which logbuch requires in either build. logbuch still
  checks every annotation, so a build fails with the flag where it fails
  without it, and with the same error. `Logbuch.settings` returns the defaults,
  and `Logbuch.configure` only type-checks its block, without running it, and
  returns the defaults too: the settings never change, nothing else the block
  does happens, the `LOGBUCH_MAX_*` variables are not read, and a setter's
  value is checked only if it is a literal. A `Logbuch.convert` still converts
  as with tracing on, but writes the whole `inspect` or `to_s` text of a value
  before it cuts it, so a large or deep object costs its full text.
- `-Dlogbuch_timing=off` compiles timing out and keeps tracing.

Both flags take `on` too, which is the default, and `0` and `1` in place of
`off` and `on`; any other value fails the build.

### Which methods can be traced

logbuch traces instance methods, class methods (`def self.`), private and
protected methods, overloads, generic methods (`forall`), methods with default
values, splats, double splats, named-only parameters, external parameter names,
methods that yield, methods with a captured block (`&block`), and methods of
modules. The traced method keeps its signature, return type, visibility and its
other annotations.

logbuch traces the subclasses of a traced class too. In a module, it wraps the
traced methods in the module itself, so they are traced wherever they are
called: through any class that includes the module, through `extend self`, or
as `def self.` methods. A class that includes a traced module gets its own
`@[Logged]` methods traced too.

A traced method is logged as the type that defines it. Called on a subclass, or
through a class that includes the module, an inherited method keeps the label
and the log of its defining type, also when the subclass has a `Log` or a
`@[LogType(log: …)]` of its own: with `class Plain < Base`, `Plain.new.foo`
logs `Base#foo` under `base`. To log it as the subclass, override it there with
its own `@[Logged]` and call `super`; logbuch then logs only the override.

logbuch cannot see a private top-level module, the modules inside it, or a type
that your own `macro finished` defines, so it neither traces their `@[Logged]`
methods nor fails the build for them. Add `include Logbuch::Annotations` to
such a type to trace them. An enum cannot include a module, so `@[Logged]` on a
method of an enum fails the build; trace a method of a class, struct or module
instead.

The build also fails for:

- `@[Logged]` on an abstract method, which has no body to wrap; trace the
  implementations instead.
- `@[Logged]` on `initialize`; trace a method that creates the object instead.
- `@[Logged]` on a method that uses `with … yield`, which the wrapper cannot
  forward.
- `@[Logged]` on a method whose typed splat is followed by a named parameter
  without a default, such as `def add(*items : Item, to cart : Cart)`. Crystal
  adds the wrapper of such a method as an overload instead of replacing the
  method, so its calls would not be traced. Give that parameter a default, or
  drop the splat's type.

logbuch checks the annotations of every class, struct and module when the
program is built, whether or not the type is converted or its methods are
called, and in every build: the type's `@[LogType]`, the annotations on its
fields, and those on its methods and their parameters. In a type it cannot see,
as described above, it checks the fields, and the traced methods once the type
includes `Logbuch::Annotations`. A `log:` constant in `@[LogType]` names a log
in the traced types that inherit it, so it is checked there.

When a traced method calls the method it overrides with `super`, and that one
is traced too, logbuch logs only the outer call, with its own description and
options. It logs a recursive call, or a call of the same method on another
object, as usual. If the outer call's level is disabled, the method reached
through `super` stays silent too. A traced method that calls an overload of its
own name that a parent class or an included module defines, such as
`save(String)` calling an inherited `save(Int32)`, counts as such a call too,
so only the outer call is logged. An overload in the same class is logged as
usual.

logbuch tells one struct from another by where it is stored. A copy is another
struct, and a proc literal that uses `self` holds a copy, so a `super` call
inside such a proc is logged like a call on another object. logbuch cannot tell
apart the instances of a struct without instance variables and takes them for
one object: when a traced method of such a struct calls an inherited method of
the same name on another instance, only the outer call is logged.

Crystal copies a method that yields into every place that calls it, and the
tracing wrapper of such a method is copied with it, about 1 KB of machine code
per call site in a release build, against some 40 bytes for the untraced
method. A method that yields and is called from a hundred places adds about 100
KB to the binary when traced.

## Development

Requirements: Crystal (see `crystal` in `shard.yml`), Ruby, Rake and Docker.

| Task                          | What it does                                                                |
| ----------------------------- | --------------------------------------------------------------------------- |
| `rake setup`                  | Install the shard dependencies                                              |
| `rake deps`                   | Install the shard dependencies; `rake setup` runs it                        |
| `rake spec`                   | Run the unit tests                                                          |
| `rake "spec[path]"`           | Run one spec file or directory                                              |
| `rake spec:no_timing`         | Run the unit tests with `-Dlogbuch_timing=off`                              |
| `rake spec:off`               | Run `spec/logbuch/off_spec.cr` with `-Dlogbuch=off`                         |
| `rake spec:release_compiler`  | Run the unit tests with the released compiler CI uses, in Docker            |
| `rake spec:oldest_compiler`   | Run the unit tests with the oldest compiler `shard.yml` allows, in Docker   |
| `rake spec:all`               | Run `spec` and the four `spec:` tasks above                                 |
| `rake examples`               | Run the example programs                                                    |
| `rake "example[basic]"`       | Run one example program, here `examples/basic.cr`                           |
| `rake examples:check`         | Run the examples, also with `-Dlogbuch=off`; compare with `.work/examples/` |
| `rake examples:update`        | Save the examples' output in `.work/examples/`                              |
| `rake format`                 | Format the Crystal sources                                                  |
| `rake lint`                   | Check formatting, run Ameba (built on first use)                            |
| `rake docs`                   | Build the API docs into `.tmp/docs/`                                        |
| `rake release:plan`           | Print what `rake release` would do, and its changelog section               |
| `rake release`                | Cut a release branch and tag, update the changelog                          |
| `rake "release:notes[1.2.3]"` | Print the changelog section of a released version                           |
| `rake clean`                  | Remove the compiler cache and the API docs in `.tmp/`                       |
| `rake clobber`                | Also remove `lib/` and `.shards/`, the installed shards                     |

`rake release` pushes nothing. After you push the release branch and the tag,
the Release workflow runs the CI suite on the tagged commit and, once it
passes, publishes a GitHub release with the version's changelog section as its
notes, and, for a version without a suffix, deploys the API docs to GitHub
Pages. To publish the docs of `main` in between, such as before the first
release, run the Docs workflow by hand from the Actions tab.

## License

MIT, see [LICENSE.txt](LICENSE.txt).
