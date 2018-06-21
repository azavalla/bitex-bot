module BitstampApiWrapperStubs
  def stub_bitstamp_api_wrapper_order_book
    BitexBot::Api::Bitstamp.any_instance.stub(order_book: bitstamp_api_wrapper_order_book)
  end

  def bitstamp_api_wrapper_order_book
    BitexBot::Api::OrderBook.new(
      Time.now.to_i,
      [['30', '3'], ['25', '2'], ['20', '1.5'], ['15', '4'], ['10', '5']].map do |price, quantity|
        BitexBot::Api::OrderSummary.new(price.to_d, quantity.to_d)
      end,
      [['10', '2'], ['15', '3'], ['20', '1.5'], ['25', '3'], ['30', '3']].map do |price, quantity|
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
    transactions = 5.times.collect do |i|
      BitexBot::Api::Transaction.new(i, price, amount, (i+1).seconds.ago.to_i)
    end
  end
end

RSpec.configuration.include BitstampApiWrapperStubs
