require "yaml"
require "./spec_helper"
require "../src/logbuch"

ROOT = File.join(__DIR__, "..")

describe Logbuch do
  test "version matches shard.yml" do
    shard_version = YAML.parse(File.read(File.join(ROOT, "shard.yml")))["version"].as_s

    assert(Logbuch::VERSION == shard_version)
  end

  # CI tests the version shard.yml requires as the oldest one, read from
  # `crystal: ">= x.y.z"`, and the one .project.yaml names.
  test "shard.yml requires an oldest Crystal version no newer than the one CI tests" do
    shard = YAML.parse(File.read(File.join(ROOT, "shard.yml")))
    project = YAML.parse(File.read(File.join(ROOT, ".project.yaml")))
    oldest = shard["crystal"].as_s.lchop(">= ")
    assert oldest.matches?(/\A\d+\.\d+\.\d+\z/)
    assert SemanticVersion.parse(oldest) <= SemanticVersion.parse(project["crystal"]["version"].as_s)
  end
end
