![logbuch, structured logging for Crystal](artwork/logbuch-banner.jpg)

# logbuch

[![CI](https://github.com/jochenseeber/logbuch/actions/workflows/ci.yml/badge.svg)](https://github.com/jochenseeber/logbuch/actions/workflows/ci.yml)

Method tracing for [Crystal](https://crystal-lang.org/): annotate a method, and
logbuch logs each call with its arguments, its result and duration, or the
exception it raised. _Logbuch_ is German for logbook.

- **One annotation per method.** One `include` per program, none per type, and
  no base class. Instance and class methods, private methods, generics, splats,
  blocks and modules all work, and the traced method keeps its body, signature
  and visibility.
- **Plain stdlib `Log`.** Arguments, results and errors are `Log::Metadata`, so
  a formatter or backend, such as a JSON one, receives each value separately.
  Levels, sources and `LOG_LEVEL` work as they do for your own log lines.
- **Control over what is logged.** Set a detail level per method, and
  `@[LogAs]` per parameter and field: `:omit`, `:id`, `:summary`, `:full` or
  `:redacted`. Converters mask or summarize a value before it is logged.
- **Safe by default.** logbuch caps every value in depth, items and length. It
  logs only types that opt in by their fields, and anything else with
  `inspect`. A log backend that raises loses one line and changes nothing else.
- **Cheap when off.** A call whose level is disabled converts nothing and costs
  a few nanoseconds, without allocating. `-Dlogbuch=off` compiles tracing out.

## Usage

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

The traced method is written like any other: a plain `return` works, and an
exception passes through unchanged.

The [examples](https://github.com/jochenseeber/logbuch/tree/main/examples)
directory has a runnable program for each feature area. The
[guide](https://github.com/jochenseeber/logbuch/blob/main/GUIDE.md) describes
every annotation and option, and the
[API documentation](https://jochenseeber.github.io/logbuch/) every public type
of the latest release.

## Installation

Add the dependency to your `shard.yml` and run `shards install`:

```yaml
dependencies:
  logbuch:
    github: jochenseeber/logbuch
```

logbuch needs Crystal 1.21 or later, and `shards` on the `PATH` when your
program compiles, since it reads `Logbuch::VERSION` with `shards version`.

## Contributing

See [CONTRIBUTING.md](https://github.com/jochenseeber/logbuch/blob/main/CONTRIBUTING.md)
for the development setup and the rake tasks.

## License

MIT, see [LICENSE.txt](https://github.com/jochenseeber/logbuch/blob/main/LICENSE.txt).
