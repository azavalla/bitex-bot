FactoryBot.define do
  factory :sell_closing_flow, class: BitexBot::SellClosingFlow do
    desired_price Faker::Number.normal(100, 10).truncate(2).to_d
    quantity      Faker::Number.normal(100, 10).truncate(2).to_d
    amount        Faker::Number.normal(100, 10).truncate(2).to_d
    done          false
    crypto_profit Faker::Number.normal(5, 1).truncate(2).to_d
    fiat_profit   Faker::Number.normal(5, 1).truncate(2).to_d
    fx_rate       Faker::Number.normal(5, 1).truncate(2).to_d
  end
end
