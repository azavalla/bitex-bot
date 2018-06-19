require 'spec_helper'

describe BitstampApiWrapper do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitstamp: {
        api_key: 'YOUR_API_KEY', secret: 'YOUR_API_SECRET', client_id: 'YOUR_BITSTAMP_USERNAME'
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  let(:api_wrapper) { BitexBot::Robot.taker }

  it 'Sends User-Agent header' do
    stub_stuff =
      stub_request(:post, 'https://www.bitstamp.net/api/v2/balance/btcusd/')
        .with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    expect { api_wrapper.balance }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end

  it '#balance' do
    stub_bitstamp_balance

    balance = api_wrapper.balance
    balance.should be_a(ApiWrapper::BalanceSummary)
    balance.members.should contain_exactly(*%i[btc usd fee])

    balance.fee.should be_a(BigDecimal)

    btc = balance.btc
    btc.should be_a(ApiWrapper::Balance)
    btc.members.should contain_exactly(*%i[total reserved available])
    btc.total.should be_a(BigDecimal)
    btc.reserved.should be_a(BigDecimal)
    btc.available.should be_a(BigDecimal)

    usd = balance.usd
    usd.should be_a(ApiWrapper::Balance)
    usd.members.should contain_exactly(*%i[total reserved available])
    usd.total.should be_a(BigDecimal)
    usd.reserved.should be_a(BigDecimal)
    usd.available.should be_a(BigDecimal)
  end

  it '#cancel' do
    stub_bitstamp_orders

    api_wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_bitstamp_order_book

    order_book = api_wrapper.order_book
    order_book.should be_a(ApiWrapper::OrderBook)
    order_book.members.should contain_exactly(*%i[timestamp asks bids])

    order_book.timestamp.should be_a(Integer)
    order_boook.asks.should be_an(Array)
    order_boook.bids.should be_an(Array)

    bid = order_book.bids.sample
    bid.should be_a(ApiWrapper::OrderSummary)
    bid.members.should contain_exactly(*%i[price quantity])
    bid.price.should be_a(BigDecimal)
    bid.quantity.should be_a(BigDecimal)

    ask = order_book.asks.sample
    ask.should be_a(ApiWrapper::OrderSummary)
    ask.members.should contain_exactly(*%i[price quantity])
    ask.price.should be_a(BigDecimal)
    ask.quantity.should be_a(BigDecimal)
  end

  it '#orders' do
    stub_bitstamp_orders

    order = api_wrapper.orders.sample
    order.should be_a(ApiWrapper::Order)
    order.members.should contain_exactly(*%i[id type price amount timestamp raw])
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
    order.raw.should be_present
  end

  context '#place_order' do
    it 'raises OrderNotFound error on bitstamp errors' do
      Bitstamp.orders.stub(:buy) { raise OrderNotFound }

      expect { api_wrapper.place_order(:buy, 10, 100) }.to raise_exception(OrderNotFound)
    end
  end

  it '#transactions' do
    stub_bitstamp_transactions

    transaction = api_wrapper.transactions.sample
    transaction.should be_a(ApiWrapper::Transaction)
    transaction.members.should contain_exactly(*%i[id price amount timestamp raw])
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
    transaction.raw.should be_present
  end

  it '#user_transaction' do
    stub_bitstamp_user_transactions

    user_transaction = api_wrapper.user_transactions.sample
    user_transaction.should be_a(ApiWrapper::UserTransaction)
    user_transaction.members.should contain_exactly(*%i[order_id usd btc btc_usd fee type timestamp])
    user_transaction.usd.should be_a(BigDecimal)
    user_transaction.btc.should be_a(BigDecimal)
    user_transaction.btc_usd.should be_a(BigDecimal)
    user_transaction.order_id.should be_a(Integer)
    user_transaction.fee.should be_a(BigDecimal)
    user_transaction.type.should be_a(Integer)
    user_transaction.timestamp.should be_a(Integer)
  end

  it '#find_lost' do
    stub_bitstamp_orders

    api_wrapper.orders.all? { |o| api_wrapper.find_lost(o.type, o.price, o.amount).present? }
  end
end
