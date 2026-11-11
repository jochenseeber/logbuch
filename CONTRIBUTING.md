# Contributing

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

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/);
`rake release` builds `CHANGELOG.md` from them.
