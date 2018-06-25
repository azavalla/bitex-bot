module BitstampApiWrapperStubs
  def stub_bitstamp_api_wrapper_order_book
    BitexBot::Api::Bitstamp.any_instance.stub(order_book: bitstamp_api_wrapper_order_book)
  end

  def bitstamp_api_wrapper_order_book
    BitexBot::Api::OrderBook.new(
      Time.now.to_i,
      [%w[30 3], %w[25 2], %w[20 1.5], %w[15 4], %w[10 5]].map do |price, quantity|
        BitexBot::Api::OrderSummary.new(price.to_d, quantity.to_d)
      end,
      [%w[10 2], %w[15 3], %w[20 1.5], %w[25 3], %w[30 3]].map do |price, quantity|
        BitexBot::Api::OrderSummary.new(price.to_d, quantity.to_d)
      end
    )
  end

  def stub_bitstamp_api_wrapper_balance(usd = nil, coin = nil, fee = nil)
    BitexBot::Api::Bitstamp.any_instance.stub(:balance) do
      BitexBot::Api::BalanceSummary.new(
        BitexBot::Api::Balance.new((coin || 10).to_d, 0.to_d, (coin || 10).to_d),
        BitexBot::Api::Balance.new((usd || 100).to_d, 0.to_d, (usd || 100).to_d),
        0.5.to_d
      )
    end
  end

  def bitstamp_api_wrapper_transactions_stub(price = 30.to_d, amount = 1.to_d)
    5.times.map { |i| BitexBot::Api::Transaction.new(i, price, amount, (i + 1).seconds.ago.to_i) }
  end
end

RSpec.configuration.include BitstampApiWrapperStubs
