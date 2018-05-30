FactoryBot.define do
  factory :bitex_buy, class: Bitex::Buy do
    id         12_345_678
    bid_id     12_345
    order_book :btc_usd
    quantity   2
    amount     600
    fee        0.05
    price      300
    created_at Time.now
  end
end
