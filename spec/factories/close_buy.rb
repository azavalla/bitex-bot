FactoryBot.define do
  factory :close_buy, class: BitexBot::CloseBuy do
    amount   Faker::Number.normal(100, 10).truncate(2).to_d
    quantity Faker::Number.normal(100, 10).truncate(2).to_d
    order_id Faker::Number.between(1, 1_000)
  end
end
