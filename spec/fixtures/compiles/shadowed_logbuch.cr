require "../../../src/logbuch"

# An application module named like the shard must not confuse it.
module MyApp
  module Logbuch
  end

  @[::Logbuch::Annotations::LogType]
  class Order
    @[::Logbuch::Annotations::LogAs(:omit)]
    getter card = "4111"
    getter id = "o-1"
  end

  class Checkout
    include ::Logbuch::Tracing

    @[::Logbuch::Annotations::Logged]
    def place(@[::Logbuch::Annotations::LogAs(:summary, cap: 2)] tags : Array(String), order : Order) : Int32
      tags.size
    end
  end
end

MyApp::Checkout.new.place(["a"], MyApp::Order.new)
