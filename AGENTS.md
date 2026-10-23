# Agent Notes

Usage, installation and development tasks are documented in `README.md`.

## General

The human operating this repository may be wrong about anything.

Assume the user has little knowledge of the codebase, language, architecture,
and tools; existing code may be accidental, broken, outdated, or based on
misunderstandings; user instructions may describe the desired outcome
incorrectly. Do not blindly obey implementation suggestions.

Your job is to produce the best working result.

Before changing code: inspect the repository. Understand how the system
actually works. Verify assumptions from code, tests, documentation, and
available tools. Prefer simple, robust, idiomatic solutions. When the user's
proposed solution is bad, suggest a better one.

Do not preserve broken architecture merely because it already exists.

Never fake success. Run builds, tests, linters, and relevant checks whenever
possible. Use Superpowers when available.

Treat yourself as the senior engineer responsible for the final result.

## Layout

- Library shard, no binaries. `src/logbuch.cr` is the public entry point and
  requires the files in `src/logbuch/`, one per concern.
- `src/logbuch/tracing.cr`: `Logbuch::Tracing` and the `macro finished` hook
  that wraps annotated methods (`__wrap_methods`, emitted `verbatim` so its
  macro code runs in the traced type), for classes, structs and modules. It
  reads `@[Logged]` and each method's `@[LogError]` and `@[LogAccept]`
  annotations, each of which traces the method, and generates the `case` that
  picks the level and stack trace of an error line or logs an accepted
  exception as the result. A top-level `macro finished` adds
  `include Logbuch::Tracing` to every type with a traced method that lacks it,
  and fails the build for a private one.
- The annotations are checked at build time, in every build, whether or not a
  type is converted or a method called: the top-level `macro finished` checks
  every type's `@[LogType]` and the annotations of its untraced methods and
  their parameters; `__wrap_methods` the traced methods, whose annotations need
  the type's scope, and their logs, messages and parameter limits, by typing a
  method in the type's body; `Logbuch.__check_fields` in `field_rules.cr` the
  fields, from a top-level `typeof`. Instance variables are unknown in a
  `macro finished`, so `__check_limit_target`, which reads them, runs in those
  methods. The per-use code (`__object_to_trace`,
  `Exception#__logbuch_stacktrace?`) checks nothing.
- `src/logbuch/tracer.cr`: `Logbuch::Tracer`, which converts one traced value:
  it carries the detail and the limits for the value being converted
  (`__convert_items` converts each item of a collection with the options of an
  `items(...)`, through the collection's `__logbuch_items`), and the path of
  the objects that take a level (`__logbuch_level?`, by the ancestor that
  defines `to_trace`: all but strings and the classes in `VALUE_TYPES`, such as
  `URI`), which cuts cycles and limits nesting, plus counts of the structs
  being converted: those that take a level (logged by their fields or
  `inspect`, `Set`, `Slice`, tuples and named tuples) count towards the depth
  limit like the path, the others, and the objects that take none, towards
  `DEPTH_CEILING` only. An object at `Id`, in a cycle or past the depth limit
  converts to its identity (`__identity`): its `:id` field values as
  `__logbuch_key` gives them, else `#<Type:0x…>`, `#<Type>` or its `inspect`
  text; `@identities` ends `:id` fields that lead back in `…`.
  `to_trace(tracer)` is the conversion protocol, and `tracer.convert(child)`
  the way to recurse; a `Logbuch.convert` or a traced call meanwhile nests in
  the fiber's busy tracer (`__nest`), keeping its path.
  `src/logbuch/convert.cr` has `Logbuch.convert` and the `__convert` the
  generated wrappers call.
- `src/logbuch/values.cr` and `src/logbuch/fields.cr`: `to_trace` for stdlib
  types and for objects; `fields.cr` also replaces `Reference#inspect`,
  `Struct#inspect` and their `pretty_print`, which mask an opted-in type's
  fields by its `@[LogType(inspect:)]` in every build and call `previous_def`
  for any other type. Each def there that expands `__object_to_trace` names
  `{% @type %}` in its own body: Crystal builds a def per concrete type only
  when its body uses `@type` in macro code, else once for a virtual parent
  type, whose fields an object of a subclass would then show. The stdlib
  collections in `COLLECTION_TYPES` (`Deque`, `Set`) and value types in
  `VALUE_TYPES` (`UUID`, `URI`, `Path` and such), which not every program has,
  get theirs from a top-level `macro finished` in `values.cr`, only when
  `parse_type` resolves the name to that class or struct and it has no
  `to_trace` yet, a generic one reopened with its own type parameters; never
  require their libraries or name them outside that hook (see the prelude rule
  under Conventions). `src/logbuch/field_rules.cr` holds the field detail rules
  both `Reference` and `Struct` expand, in `to_trace`, in `__logbuch_identity`,
  which writes the identity, and in `__logbuch_key`, which writes it from its
  `:id` fields (a hash key, converted at `Id`, logs it too), `__convert_as`,
  which expands a `@[LogAs]` into the conversion of a field or, from
  `__wrap_methods`, a parameter, `__check_log_as`, which checks a `@[LogAs]` on
  a parameter or field, `__check_limit_target`, which reads `COLLECTION_TYPES`
  and `VALUE_TYPES` as text, and `__check_fields`.
- `src/logbuch/annotations.cr`: `Logbuch::Annotations`, which defines `Logged`
  for methods, `LogAs` for parameters and fields, `LogError` and `LogAccept`
  for traced methods, and `LogType` for types. logbuch never includes it at the
  top level itself, so it adds no names to a program; a program does, for the
  short names in every file. Its `macro included` does nothing at the top
  level, and includes `Logbuch::Tracing` into a type that includes it, which a
  private type needs. logbuch's own code uses the full names.
  `src/logbuch/detail.cr`: `Logbuch::Detail`, and `LEVEL_NAMES` and
  `DETAIL_NAMES`, the forms a level or a detail takes in an annotation (a
  symbol or a `Log::Severity` or `Logbuch::Detail` path); every macro that
  reads a level or a detail looks it up there.
- `src/logbuch/line_data.cr`: `__line` writes one trace line, out of line so
  every wrapper shares it, and rescues a failing log backend so it never
  changes what a traced method does; `__error` writes an error line, with the
  exception in full the first time and its type after that, at the severity the
  method's `@[LogError]` sets, and attaches it unless that `@[LogError]`'s
  `stacktrace:` or `Exception#__logbuch_stacktrace?`, which reads the exception
  class's `@[LogType(stacktrace:)]`, says no; `__data` builds a line's data
  from `method` and named tuple entries.
- `src/logbuch/logs.cr`: the helpers that resolve a `log:` option; the macros
  that check and expand it are in `tracing.cr`.
- `src/logbuch/messages.cr`: `Logbuch::Messages`, the default message
  converters (`entry_message`, `exit_message`, `error_message`) a program can
  redefine; `__wrap_methods` puts each expansion in a private constant of the
  traced type (`LOGBUCH_ENTRY_<n>` and its siblings) and types a generated
  check, in the type's body and the wrapper, that fails every build for one
  that is not a `String`. Specs that replace them run a program of their own
  from `spec/fixtures/programs/`.
- `src/logbuch/locks.cr`: `Logbuch.__locked`, which takes the lock that `lock:`
  names unless the current fiber holds that `Sync::Mutex` already.
- `src/logbuch/limits.cr`: `MAX_DEPTH`, `MAX_CAP`, `MAX_LENGTH` and the helpers
  that apply them; `__limited` cuts the text an `inspect` or `to_s` writes,
  with `LimitedIO` or, with `-Dlogbuch=off`, which leaves that `IO` out, after
  the whole text is written. `src/logbuch/settings.cr`: `Logbuch.configure`, a
  macro that fails the build for a literal out of range and, with
  `-Dlogbuch=off`, only types its block against `Configuration#__dsl`,
  `Logbuch.settings` and the `LOGBUCH_MAX_*` variables; the settings in effect
  are one immutable `Settings` swapped atomically, which `Tracer.__start` reads
  once per conversion, and the constants are their defaults, which are all
  `-Dlogbuch=off` has. A new setting is a `Setting` member plus a getter and a
  setter there, and its maximum in the macro. `fiber_state.cr` keeps the
  fiber's reusable tracer and the traced call the fiber is logging, so a traced
  method reached through `super` stays silent. The call names its receiver by
  `__logbuch_receiver`, which the wrapper calls on `self`, since passing a
  struct copies it: the type id, with a reference's object id or a struct's
  address, read from its first instance variable because Crystal rejects
  `pointerof(self)`. With `-Dlogbuch=off`, a program that calls no
  `Logbuch.convert` must compile no logbuch code: define nothing it reaches
  without a call, such as a subclass of `IO` or class variables with an
  initializer. Every class, struct and enum leaves its name in a binary, so the
  off build defines only the public ones and what they need;
  `spec/fixtures/programs/compiled_out.cr` and `off_spec.cr` check both.
- One spec file per unit under `spec/logbuch/`; shared sample types in
  `spec/support/samples.cr`; `spec/fixtures/compile_errors/` holds programs
  that must fail to compile, checked with `compile_error` from
  `spec/spec_helper.cr`; `spec/logbuch/checks_spec.cr` expects each to fail
  with `-Dlogbuch=off` with the same error, except those it lists;
  `spec/fixtures/programs/` holds programs that `run_program` builds once and
  runs as child processes, for behavior fixed once per process, such as reading
  the environment variables; a fixture whose first line is
  `# build: <compiler arguments>`, such as `--prelude=empty`, is built with
  them. `spec/support/own_prelude.cr` is the smallest prelude, for this
  Crystal, that `log` and logbuch build with. microtest's `describe` takes a
  unique identifier, not a string.
- `examples/` holds runnable example programs, one per feature area, listed in
  `examples/README.md`; `rake examples` runs them. `rake examples:check`, which
  CI runs too, runs them, compares their output with the files saved in
  `.work/examples/` and runs them with `-Dlogbuch=off`. Those files are local
  and not committed, so CI only runs the examples; `rake examples:update` saves
  them, before a change to compare against and after an intended one. Keep the
  examples in step with new features.
- `rakelib/crystal.rb` defines the Crystal tasks; `support.rb`, `changelog.rb`
  and `release.rb` are language-agnostic release helpers.
- `.github/workflows/ci.yml` runs the suite and `rake docs` on every branch
  push; `release.yml` runs it on each version tag `rake release` creates,
  through `workflow_call`, then publishes a GitHub release whose notes
  `rake release:notes` prints, and, for a tag without a suffix, the API docs on
  GitHub Pages through `docs.yml`, which can also be run by hand from `main` to
  publish the docs of `main`. `ci.yml` cancels a run that a newer push to the
  same branch or pull request supersedes, never one for a tag.

## Conventions

- Follow the `my:development` and `my:development-crystal` skills (named
  parameters with a `*` splat, typed exceptions, happy path returned last).
- Assume nothing about the prelude: a program may build with a prelude of its
  own, such as `--prelude=empty` plus the requires it picks. Each source file
  requires the stdlib files of the stdlib types its own code names, reopens or
  calls, such as `sync/mutex` in `locks.cr`, even those the default prelude
  loads. A stdlib type logbuch does not use itself, such as `Deque` or `URI`,
  is never required nor reopened; it gets its `to_trace` from the
  `macro finished` at the end of `values.cr`, only when the program has it,
  through `COLLECTION_TYPES` or `VALUE_TYPES`, and a macro that compares with
  such a type resolves it with `parse_type(...).resolve?` first. The types the
  compiler declares itself, such as `Object`, `Array`, `Hash`, `Slice`, `Tuple`
  or `Exception`, exist in every program and may be reopened.
- Tests use microtest's `assert` macros, not the stdlib `spec` module.
- Measure durations with `Time.instant` / `#elapsed`, never `Time.monotonic`.
- Commits follow Conventional Commits; `CHANGELOG.md` is generated from them by
  `rake release`.

## Building

- Use the `rake` tasks instead of directly running `crystal`, `shards`, or
  `ameba`. Run `rake -T` to list them.
- `rake setup` (install dependencies), `rake spec` (`rake "spec[path]"` for one
  file), `rake format`, `rake lint` (format check plus ameba; builds the ameba
  binary on first use), `rake release` (`rake release:plan` prints what it
  would do and writes nothing).
- Run `rake spec:all` (the whole suite in the default and
  `-Dlogbuch_timing=off` builds, plus `spec/logbuch/off_spec.cr` with
  `-Dlogbuch=off`, plus the default build with the released compiler CI uses
  and with the oldest one `shard.yml` allows) and `rake lint` before
  committing; fix all warnings. `spec:release_compiler` and
  `spec:oldest_compiler` run those last two in the compilers' Docker images:
  the local `crystal` may be a build with fixes no release has, which hides
  compiler bugs users hit.
- The rake tasks keep the compiler cache in `.tmp/crystal` (`rake clean`
  removes it), so spec runs in other projects cannot overwrite this project's
  test binary.
- The Crystal version used by CI is `crystal.version` in `.project.yaml`. The
  oldest supported one is the floor of `crystal: ">= x.y.z"` in `shard.yml`,
  which CI tests as well.
