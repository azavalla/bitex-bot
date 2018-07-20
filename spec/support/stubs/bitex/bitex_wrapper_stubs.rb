module BitexApiWrapperStubs
  def stub_bitex_wrapper_profile
    raise 'implement me'
  end

  def stub_bitex_api_wrapper_balance(usd = nil, coin = nil, fee = nil)
    BitexBot::Api::Bitex.any_instance.stub(balance: bitex_api_wrapper_order_book(usd, coin, fee))
  end

  def bitex_api_wrapper_balance_stub(usd = nil, coin = nil, fee = nil)
    BitexBot::Api::BalanceSummary.new(
      BitexBot::Api::Balance.new((coin || 10).to_d, 0.to_d, (coin || 10).to_d),
      BitexBot::Api::Balance.new((usd || 100).to_d, 0.to_d, (usd || 100).to_d),
      0.5.to_d
    )
  end

  def stub_bitex_wrapper_order_book
    BitexBot::Api::Bitex.any_instance.stub(order_book: bitex_api_wrapper_order_book)
  end

  def bitex_api_wrapper_order_book
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

  def stub_bitex_wrapper_orders
    raise 'implement me'
  end

  def stub_bitex_wrapper_transactions(*extra_transactions)
    Bitex::Trade.stub(all: bitex_api_wrapper_order_book)
  end

  def bitex_api_wrapper_transactions_stub
     [build(:bitex_buy), build(:bitex_sell)].map do |raw|
      BitexBot::Api::Transaction.new(raw.id, raw.price, raw.amount, raw.created_at.to_i, raw)
    end
  end

  def stub_bitex_warapper_user_transactions
    raise 'implement me'
  end
end

RSpec.configuration.include BitexApiWrapperStubs
