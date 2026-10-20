# frozen_string_literal: true

require "open3"
require_relative "support"
require_relative "release"

# Crystal-specific project configuration and tasks for a library shard: no
# build targets or binaries, just dependencies, specs, formatting, linting and
# releases. Crystal::Project holds the project data and knows how to define its
# tasks. The main Rakefile builds one via Crystal::Project.create and calls
# #define_tasks on it.
module Crystal
  # The shards manifest — the single source of truth for the version.
  SHARD_PATH = "shard.yml"

  # The ameba binary. Recent ameba versions ship no postinstall step, so a fresh
  # `shards install` leaves only the sources and the lint task builds it.
  AMEBA_BIN = "lib/ameba/bin/ameba"

  # The compiler cache of this project. `crystal spec` writes its test binary
  # under a fixed name in the cache directory, so spec runs that share the
  # default cache, in this project or another one, overwrite each other's
  # binary and fail at random.
  CACHE_DIR = ".tmp/crystal"

  # Where `rake docs` writes the API docs. `crystal docs` defaults to docs/,
  # which holds this project's design documents.
  DOCS_DIR = ".tmp/docs"

  # All Crystal-specific project data plus task definitions. Includes Rake::DSL
  # so its methods (and the task action blocks, which run with the instance as
  # self) can call task/desc/sh/etc.
  Project = Data.define(:name, :platform, :src_dir, :spec_dir, :examples_dir) do
    include Rake::DSL

    # On macOS, Crystal auto-adds -fuse-ld=mold, which Apple's clang rejects.
    # Supplying our own -fuse-ld= disables that and forces Apple's ld; no-op elsewhere.
    def link_args
      platform.ostype == "darwin" ? ["--link-flags=-fuse-ld=/usr/bin/ld"] : []
    end

    # The link arguments as a string to append to a command line.
    def link_flags
      link_args.map { |arg| " #{arg}" }.join
    end

    # The Docker image of the released Crystal version CI tests with
    # (`crystal.version` in .project.yaml). A locally built compiler can carry
    # fixes a release lacks, so the specs also run with this one.
    def ci_image
      version = YAML.load_file(".project.yaml").dig("crystal", "version")
      "crystallang/crystal:#{version}-alpine"
    end

    # The Docker image of the oldest Crystal version the shard supports, the
    # one `crystal: ">= x.y.z"` in shard.yml names, which CI tests too.
    def oldest_image
      requirement = YAML.load_file(SHARD_PATH).fetch("crystal")
      version = requirement[%r{\A>=\s*(\d+\.\d+\.\d+)\z}, 1]
      abort "#{SHARD_PATH}: crystal must be \">= x.y.z\", not #{requirement.inspect}" unless version
      "crystallang/crystal:#{version}-alpine"
    end

    # Run the specs in the Docker *image* for *task*. The working tree is
    # copied into the container without lib, which holds shards set up for the
    # host and is a symlink in a worktree; the container installs its own.
    def docker_spec(image, task:)
      abort "#{task} needs Docker" unless capture("docker", "version", "--format", "{{.Server.Version}}")
      sh "docker", "run", "--rm", "-v", "#{Dir.pwd}:/src:ro", image, "sh", "-c", <<~SH
        set -e
        mkdir /w
        tar -C /src --exclude=./.tmp --exclude=./lib -cf - . | tar -C /w -xf -
        cd /w
        shards install --skip-postinstall --skip-executables
        crystal spec
      SH
    end

    # Write *version* to shard.yml, the one place that holds it; the shard's
    # code reads it from there with `shards version`.
    def write_version(version)
      raw = File.read(SHARD_PATH)
      pattern = %r{^version:.*$}
      abort "Could not find the version in #{SHARD_PATH}" unless raw.match?(pattern)
      File.write(SHARD_PATH, raw.sub(pattern, "version: #{version}"))
    end

    # The names of the example programs in the examples directory.
    def example_names
      Dir.glob(File.join(examples_dir, "*.cr")).map { |path| File.basename(path, ".cr") }.sort
    end

    # Define the tasks that run the example programs.
    def define_example_tasks
      desc "Run an example (args: name, e.g. basic for examples/basic.cr)"
      task "example", [:name] do |_task, args|
        abort "usage: rake \"example[name]\"; examples: #{example_names.join(", ")}" unless args[:name]
        sh "crystal run #{examples_dir}/#{args[:name]}.cr#{link_flags}"
      end

      desc "Run all examples"
      task "examples" do
        example_names.each { |name| sh "crystal run #{examples_dir}/#{name}.cr#{link_flags}" }
      end

      namespace "examples" do
        desc "Run the examples, compare their output with #{example_output_dir} where it is saved, " \
             "and run them with -Dlogbuch=off"
        task "check" do
          names = example_names
          compared = names.to_h { |name| [name, example_compare(name)] }
          failed = names.select { |name| compared[name] == :differs }
          failed += names.reject { |name| example_runs_off?(name) }
          abort "examples failed: #{failed.uniq.join(", ")}" unless failed.empty?

          matched = compared.count { |_name, result| result == :matched }
          unsaved = names.size - matched
          summary = "#{names.size} examples ran, #{matched} matched their saved output"
          summary += " (#{unsaved} have none in #{example_output_dir})" if unsaved.positive?
          puts "#{summary}, #{names.size} ran with -Dlogbuch=off"
        end

        desc "Save the examples' output in #{example_output_dir}, which examples:check compares against"
        task "update" do
          mkdir_p example_output_dir, verbose: false
          example_names.each do |name|
            File.write(example_output_path(name), example_output(name))
            puts "updated #{example_output_path(name)}"
          end
        end
      end
    end

    # Where the examples' expected output is saved: a local, uncommitted
    # directory, so a checkout without it, such as CI's, only runs them.
    def example_output_dir
      ".work/examples"
    end

    # Where the expected output of example *name* is saved.
    def example_output_path(name)
      File.join(example_output_dir, "#{name}.out")
    end

    # Run example *name* with timing compiled out, so its output does not change
    # from run to run, and return what it printed, stdout and stderr together,
    # with object addresses masked. Aborts if the example fails.
    def example_output(name)
      path = File.join(examples_dir, "#{name}.cr")
      output, status = Open3.capture2e("crystal", "run", "-Dlogbuch_timing=off", *link_args, path)
      abort "#{output}#{path}: exited with #{status.exitstatus}" unless status.success?
      output.gsub(%r{0x[0-9a-f]+}, "0x…")
    end

    # Runs example *name* and compares what it prints with its saved output:
    # :matched, :differs, after printing a unified diff, or :unsaved when no
    # output is saved, where running it is enough. Aborts if the example fails.
    def example_compare(name)
      output = example_output(name)
      expected = example_output_path(name)
      return :unsaved unless File.exist?(expected)

      diff, status = Open3.capture2e("diff", "-u", expected, "-", stdin_data: output)
      return :matched if status.success?

      puts diff, "#{examples_dir}/#{name}.cr: output differs from #{expected}"
      :differs
    end

    # Whether example *name* still compiles and runs with tracing compiled out.
    def example_runs_off?(name)
      path = File.join(examples_dir, "#{name}.cr")
      output, status = Open3.capture2e("crystal", "run", "-Dlogbuch=off", *link_args, path)
      return true if status.success?

      puts output, "#{path}: fails with -Dlogbuch=off"
      false
    end

    # Point the compiler of every task at the project's own cache; `rake clean`
    # removes it.
    def use_project_cache
      ENV["CRYSTAL_CACHE_DIR"] = File.expand_path(CACHE_DIR)
      CLEAN.include(CACHE_DIR)
    end

    # The version in shard.yml.
    def version
      File.read(SHARD_PATH)[%r{^version:\s*(\S+)}, 1]
    end

    # Define the task that builds the API docs. It removes the previous output
    # first, so no page of a removed type is left behind. `crystal docs` does
    # not link, so it needs no link flags. The README is the docs' index page,
    # so the examples it links relatively are copied next to it.
    def define_docs_task
      CLEAN.include(DOCS_DIR)

      desc "Build the API docs into #{DOCS_DIR}"
      task "docs" do
        rm_rf DOCS_DIR
        sh "crystal", "docs", "--output=#{DOCS_DIR}", "--project-name=#{name}", "--project-version=#{version}"
        cp_r examples_dir, DOCS_DIR
      end
    end

    # Define all tasks for this project.
    def define_tasks
      use_project_cache
      CLOBBER.include("lib", ".shards")

      desc "Install Crystal dependencies"
      task "deps" do
        sh "shards install"
      end

      desc "Set up the project (install dependencies)"
      task "setup" => "deps"

      desc "Run unit tests (args: path [spec file or directory, default all])"
      task "spec", [:path] do |_task, args|
        cmd = "crystal spec"
        cmd += " #{args[:path]}" if args[:path]
        sh "#{cmd}#{link_flags}"
      end

      namespace "spec" do
        desc "Run unit tests with timing compiled out (-Dlogbuch_timing=off)"
        task "no_timing" do
          sh "crystal spec -Dlogbuch_timing=off#{link_flags}"
        end

        desc "Run the off spec with tracing compiled out (-Dlogbuch=off)"
        task "off" do
          sh "crystal spec #{spec_dir}/logbuch/off_spec.cr -Dlogbuch=off#{link_flags}"
        end

        desc "Run unit tests with the released compiler CI uses, in its Docker image"
        task "release_compiler" do |task|
          docker_spec(ci_image, task: task.name)
        end

        desc "Run unit tests with the oldest compiler shard.yml allows, in its Docker image"
        task "oldest_compiler" do |task|
          docker_spec(oldest_image, task: task.name)
        end

        desc "Run unit tests in every build variant and with the released and the oldest compiler"
        task "all" => ["spec", "spec:no_timing", "spec:off", "spec:release_compiler", "spec:oldest_compiler"]
      end

      define_example_tasks
      define_docs_task

      desc "Format Crystal sources"
      task "format" do
        sh "crystal tool format #{src_dir} #{spec_dir} #{examples_dir}"
      end

      file AMEBA_BIN do
        sh "crystal build lib/ameba/src/cli.cr -o #{AMEBA_BIN} --release#{link_flags}"
      end

      desc "Check formatting and run the Ameba linter"
      task "lint", [:no_color] => AMEBA_BIN do |_task, args|
        sh "crystal tool format --check #{src_dir} #{spec_dir} #{examples_dir}"
        cmd = AMEBA_BIN
        cmd += " --no-color" if args[:no_color]
        sh cmd
      end

      # Release: shard.yml holds the version.
      define_release_task(
        name: "release",
        read_version: -> { version },
        write_version: ->(version) { write_version(version) },
        version_files: [SHARD_PATH]
      )
    end

    # Build a Project by inspecting shard.yml and detecting the host.
    def self.create
      shard = YAML.load_file(SHARD_PATH)

      new(
        name: shard.fetch("name"),
        platform: ::Platform.detect,
        src_dir: "src",
        spec_dir: "spec",
        examples_dir: "examples"
      )
    end
  end
end
