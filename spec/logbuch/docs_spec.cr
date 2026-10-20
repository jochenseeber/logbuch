require "../spec_helper"

# Every doc comment in src/ that hides its item with :nodoc: must start with
# it: the doc generator hides an item only when its comment begins with
# :nodoc:, and shows it with the marker as text otherwise.
def misplaced_nodoc : Array(String)
  found = [] of String
  Dir.glob(File.join(__DIR__, "../../src/**/*.cr")).sort.each do |path|
    block = [] of String
    File.read_lines(path).each_with_index(1) do |line, number|
      if line.strip.starts_with?("#")
        block << line.strip
      else
        if block.any?(&.== "# :nodoc:") && block.first != "# :nodoc:"
          found << "#{File.basename(path)}:#{number}"
        end
        block.clear
      end
    end
  end
  found
end

describe DocComments do
  test "internal items put :nodoc: first so the doc generator hides them" do
    assert misplaced_nodoc.empty?
  end
end
