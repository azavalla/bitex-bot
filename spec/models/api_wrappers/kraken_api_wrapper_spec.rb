require 'spec_helper'

describe KrakenApiWrapper do
  let(:api_wrapper) { described_class }
  let(:api_client) { api_wrapper.client }
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      kraken: {
        api_key: 'your_api_key', api_secret: 'your_api_secret'
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_stuff =
      stub_request(:get, 'https://api.kraken.com/0/public/Depth?pair=XBTUSD')
        .with(headers: { 'User-Agent': BitexBot.user_agent })

    # We don't care about the response
    expect { api_wrapper.order_book }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end

  it '#balance' do
    stub_kraken_private_client
    stub_kraken_orders
    stub_kraken_balance
    stub_kraken_trade_volume

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
    stub_kraken_private_client
    stub_kraken_orders

    api_wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_kraken_public_client
    stub_kraken_order_book

    order_book = api_wrapper.order_book

    order_book.should be_a(ApiWrapper::OrderBook)
    order_book.members.should contain_exactly(*%i[timestamp asks bids])

    order_book.timestamp.should be_a(Integer)

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
    stub_kraken_private_client
    stub_kraken_orders

    order = api_wrapper.orders.sample
    order.should be_a(ApiWrapper::Order)
    order.members.should contain_exactly(*%i[id type price amount timestamp raw_order])
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
    order.raw_order.should be_present
  end

  it '#transactions' do
    stub_kraken_public_client
    stub_kraken_transactions

    transaction = api_wrapper.transactions.sample
    transaction.should be_a(ApiWrapper::Transaction)
    transaction.members.should contain_exactly(*%i[id price amount timestamp])
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  it '#user_transaction' do
    api_wrapper.user_transactions.should be_a(Array)
    api_wrapper.user_transactions.empty?.should be_truthy
  end

  it '#find_lost' do
    stub_kraken_private_client
    stub_kraken_orders

    described_class.orders.all? { |o| described_class.find_lost(o.type, o.price, o.amount).present? }
  end
end
