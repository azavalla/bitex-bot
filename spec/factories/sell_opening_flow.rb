FactoryBot.define do
  factory :sell_opening_flow, class: BitexBot::SellOpeningFlow do
    order_id                12_345
    price                   300
    value_to_use            2
    suggested_closing_price 290
    status                  'executing'
  end

  factory :other_sell_opening_flow, class: BitexBot::SellOpeningFlow do
    order_id                2
    price                   400
    value_to_use            1
    suggested_closing_price 390
    status                  'executing'
  end
end
