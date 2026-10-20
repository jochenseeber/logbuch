require "../../src/logbuch"

class Card
  include Logbuch::Annotations

  @[LogAs(:id)]
  getter id : String = "c1"
  getter label : String = "visa"
  getter tags : Array(String) = ["x"]
  getter owner : Card? = nil
  @[LogAs(:full)]
  getter note : String = "n"
  @[LogAs(:omit)]
  getter number : String = "4111"
  property link : Card? = nil
  getter mixed : String | Array(String) = "m"
  getter count : Int32 = 3
  getter active : Bool? = true
end
