module Logbuch
  # The converters that build the messages of a traced method's lines: the
  # entry line's, the exit line's and the error line's.
  #
  # Each one is a macro that takes *call*, a named tuple literal of what is
  # known about the traced method when the program compiles, and expands to
  # the message, which must be a `String`:
  #
  # | Key            | Example                        | Notes                                 |
  # | -------------- | ------------------------------ | ------------------------------------- |
  # | `type`         | `"Shop::Checkout"`             | without generic arguments             |
  # | `method`       | `"place"`                      |                                       |
  # | `class_method` | `false`                        |                                       |
  # | `label`        | `"Shop::Checkout#place"`       | the `method` value of the line's data |
  # | `description`  | `"placing the order"` or `nil` | the annotation's string, as written   |
  # | `level`        | `"trace"`                      | the method's level                    |
  # | `params`       | `["order", "coupon"]`          | the parameters' internal names        |
  #
  # `params` lists a splat and a double splat under their bare names, and
  # parameters marked `@[LogAs(:omit)]` or `@[LogAs(:redacted)]` too; it leaves
  # out an unnamed `*` and the block parameter.
  #
  # A program replaces a converter by reopening this module after requiring
  # logbuch. The wrappers are generated once the whole program is read, so the
  # last definition wins, wherever it is:
  #
  # ```
  # module Logbuch::Messages
  #   macro entry_message(call)
  #     {{ "→ #{call[:label].id}" }}
  #   end
  # end
  # ```
  #
  # Each message is kept in a constant of the traced type, which the traced
  # call reads. A converter therefore cannot refer to the call's arguments, an
  # expansion that is a string literal costs nothing per call, and a computed
  # one is computed once, the first time it is read.
  module Messages
    # The entry line's message: the description, such as
    # `placing the order`, or `>` and the label, such as
    # `>Shop::Checkout#place`.
    macro entry_message(call)
      {% if call[:description] %}{{ call[:description] }}{% else %}{{ ">" + call[:label] }}{% end %}
    end

    # The exit line's message: `done` and the description, such as
    # `done placing the order`, or `<` and the label, such as
    # `<Shop::Checkout#place`.
    macro exit_message(call)
      {% if call[:description] %}{{ "done " + call[:description] }}{% else %}{{ "<" + call[:label] }}{% end %}
    end

    # The error line's message: `error` and the description, such as
    # `error placing the order`, or `!` and the label, such as
    # `!Shop::Checkout#place`.
    macro error_message(call)
      {% if call[:description] %}{{ "error " + call[:description] }}{% else %}{{ "!" + call[:label] }}{% end %}
    end
  end
end
