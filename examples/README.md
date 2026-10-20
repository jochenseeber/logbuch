# Examples

Small programs that show what logbuch does. Each one prints its trace lines
with a short comment before each part.

| Example                 | Shows                                                                                                                                                                                                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `basic.cr`              | `@[Logged]`, descriptions as messages, `return` in a traced method, error lines, `@[LogAccept]`, `Nil` methods                                                                                                                                                                   |
| `errors.cr`             | error lines and stack traces; `@[LogType(stacktrace:)]` on exception types, `@[LogError]` with types, a level and `stacktrace:`, and without types; `@[LogAccept]` with a level and `stacktrace:`; either one tracing a method without `@[Logged]`; causes                       |
| `data_types.cr`         | how each kind of value is logged: numbers, strings, tuples, records and classes, arrays, hashes and sets, stdlib types such as `URI` and `UUID`, identities with and without `:id` fields, and `items(...)`                                                                      |
| `detail_levels.cr`      | the detail in `@[Logged]`, also as a `Logbuch::Detail` member, `@[LogAs]` on fields and on a parameter of an `:omit` method, `@[LogType]`, default field rules, structs, identities and stdlib value types at `:id`, cycles, `cap:`, `length:` and `items(...)` with a converter |
| `secrets.cr`            | `@[LogAs(:omit)]`, `@[LogAs(:redacted)]` with and without a detail, converters, annotations on `initialize` parameters, a hash key logged as its identity                                                                                                                        |
| `to_trace.cr`           | a `to_trace` of a type's own: `tracer.convert` with `cap:`, `length:` and a block, `tracer.detail`, a value type of the program, placeholders for a block or `to_trace` that raises, cycles                                                                                      |
| `method_kinds.cr`       | class methods, blocks with `next` and `break`, splats, captured blocks, external names and defaults, private methods, generics, structs, modules, subclasses and `super`, a private type                                                                                         |
| `levels_and_sources.cr` | the level in `@[Logged]`, also as a `Log::Severity` member, `timing:`, `slow:`, `log:` with a source name, a name below the type's log and a constant, on methods and on `@[LogType]`, `Log.setup` filtering, error lines of filtered methods, a custom `to_trace`               |
| `full_names.cr`         | the annotations without the top-level include: full names, an alias, `include Logbuch::Annotations` in one type, a program's own `LogError`                                                                                                                                      |
| `json_logging.cr`       | a backend that writes each entry as JSON, and one that reads the data by `Logbuch::Keys`                                                                                                                                                                                         |
| `shared_values.cr`      | values shared between threads, logged under their lock; the `result:` converter; a fiber name in the log context                                                                                                                                                                 |
| `messages.cr`           | replacing the message converters in `Logbuch::Messages`, placed after the traced class                                                                                                                                                                                           |
| `settings.cr`           | `Logbuch.configure`, `Logbuch.settings`, `max_depth`, the `LOGBUCH_MAX_*` variables and switching them off                                                                                                                                                                       |

## Running

From the project root:

```sh
rake "example[basic]"   # one example
rake examples           # all of them
rake examples:update    # save their output in .work/examples/ (not committed)
rake examples:check     # run them and compare their output with the saved one
```

Or with the compiler directly (on macOS, add
`--link-flags=-fuse-ld=/usr/bin/ld`):

```sh
crystal run examples/basic.cr
```

The build flags work here too:

```sh
crystal run -Dlogbuch_timing=off examples/levels_and_sources.cr   # no duration_ns
crystal run -Dlogbuch=off examples/levels_and_sources.cr         # no tracing at all
```

The examples print with a compact formatter that leaves out timestamps. The
`duration_ns` values and the addresses in `inspect` text change from run to
run; `rake examples:check` compiles timing out and masks the addresses.
