class ItbitApiWrapper
  def self.setup(settings)
    Itbit.client_key = settings.itbit.client_key
    Itbit.secret = settings.itbit.secret
    Itbit.user_id = settings.itbit.user_id
    Itbit.default_wallet_id = settings.itbit.default_wallet_id
    Itbit.sandbox = settings.sandbox
  end

  def self.transactions
    Itbit::XBTUSDMarketData.trades.collect{|t| Hashie::Mash.new(t) }
  end
  
  def self.order_book
    Itbit::XBTUSDMarketData.orders.stringify_keys
  end

  def self.balance
    balances = Itbit::Wallet.all
      .find{|i| i[:id] == Itbit.default_wallet_id }[:balances]
    usd = balances.find{|x| x[:currency] == :usd }
    btc = balances.find{|x| x[:currency] == :xbt }
    { "btc_balance" => btc[:total_balance],
      "btc_reserved" => btc[:total_balance] - btc[:available_balance],
      "btc_available" => btc[:available_balance],
      "usd_balance" => usd[:total_balance],
      "usd_reserved" => usd[:total_balance] - usd[:available_balance],
      "usd_available" => usd[:available_balance],
      "fee" => 0.5
    }
  end

  def self.orders
    Itbit::Order.all(status: :open)
  end

  # We don't need to fetch the list of transactions
  # for itbit since we wont actually use them later.
  def self.user_transactions
    []
  end
  
  def self.amount_and_quantity(order_id, transactions)
    order = Itbit::Order.find(order_id)
    [order.volume_weighted_average_price * order.amount_filled, order.amount_filled]
  end
  
  def self.place_order(type, price, quantity)
    Itbit::Order.create!(type, :xbtusd, quantity, price, wait: true)
  end
end
