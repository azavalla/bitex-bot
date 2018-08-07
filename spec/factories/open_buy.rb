FactoryBot.define do
  factory :seq_open_buy, class: BitexBot::OpenBuy do
    association :opening_flow, factory: :buy_opening_flow

    transaction_id Faker::Number.number(8)

    price          Faker::Number.normal(100, 10).truncate(2).to_d
    amount         Faker::Number.normal(100, 10).truncate(2).to_d
    quantity       Faker::Number.normal(10, 2).truncate(2).to_d
  end

  factory :open_buy, class: BitexBot::OpenBuy do
    association :opening_flow, factory: :buy_opening_flow

    transaction_id 12_345_678
    price          300
    amount         600
    quantity       2
  end

  factory :tiny_open_buy, class: BitexBot::OpenBuy do
    association :opening_flow, factory: :other_buy_opening_flow

    transaction_id 23_456_789
    price          400
    amount         4
    quantity       0.01
  end
end
