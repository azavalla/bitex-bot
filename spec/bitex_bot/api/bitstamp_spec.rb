require 'spec_helper'

describe BitexBot::Api::Bitstamp do
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

  let(:wrapper) { BitexBot::Robot.taker }
  let(:url) { 'https://www.bitstamp.net/api/v2/balance/btcusd/' }

  it 'Sends User-Agent header' do
    stub_stuff = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    expect { wrapper.balance }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end

  it '#balance' do
    stub_bitstamp_balance

    balance = wrapper.balance
    balance.should be_a(BitexBot::Api::BalanceSummary)
    balance.members.should contain_exactly(*%i[crypto fiat fee])

    balance.crypto.should be_a(BitexBot::Api::Balance)
    balance.fiat.should be_a(BitexBot::Api::Balance)
    balance.fee.should be_a(BigDecimal)

    [balance.crypto, balance.fiat].all? do |sample|
      sample.members.should contain_exactly(*%i[total reserved available])

      sample.total.should be_a(BigDecimal)
      sample.reserved.should be_a(BigDecimal)
      sample.available.should be_a(BigDecimal)
    end
  end

  it '#cancel' do
    stub_bitstamp_orders

    wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_bitstamp_order_book

    order_book = wrapper.order_book
    order_book.should be_a(BitexBot::Api::OrderBook)
    order_book.members.should contain_exactly(*%i[timestamp asks bids])

    order_book.asks.should be_an(Array)
    order_book.bids.should be_an(Array)
    order_book.timestamp.should be_a(Integer)

    [order_book.bids.sample, order_book.asks.sample].all? do |sample|
      sample.should be_a(BitexBot::Api::OrderSummary)
      sample.members.should contain_exactly(*%i[price quantity])

      sample.price.should be_a(BigDecimal)
      sample.quantity.should be_a(BigDecimal)
    end
  end

  it '#orders' do
    stub_bitstamp_orders

    wrapper.orders.should be_a(Array)

    sample = wrapper.orders.sample
    sample.should be_a(BitexBot::Api::Order)
    sample.members.should contain_exactly(*%i[id type price amount timestamp raw])

    sample.id.should be_a(String)
    sample.type.should be_a(Symbol)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    sample.raw.should be_present
    sample.raw.should be_a(Bitstamp::Order)
  end

  context '#place_order' do
    it 'raises OrderNotFound error on bitstamp errors' do
      Bitstamp.orders.stub(:buy) { raise BitexBot::Api::OrderNotFound }
      Bitstamp.orders.stub(:sell) { raise BitexBot::Api::OrderNotFound }

      expect { wrapper.place_order(:buy, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
      expect { wrapper.place_order(:sell, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
    end
  end

  it '#transactions' do
    stub_bitstamp_transactions

    wrapper.transactions.should be_a(Array)

    sample = wrapper.transactions.sample
    sample.should be_a(BitexBot::Api::Transaction)
    sample.members.should contain_exactly(*%i[id price amount timestamp raw])

    sample.id.should be_a(Integer)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    sample.raw.should be_a(Bitstamp::Transactions)
  end

  it '#user_transaction' do
    stub_bitstamp_user_transactions

    wrapper.user_transactions.should be_a(Array)

    sample = wrapper.user_transactions.sample
    sample.should be_a(BitexBot::Api::UserTransaction)
    sample.members.should contain_exactly(*%i[order_id usd btc btc_usd fee type timestamp])

    sample.usd.should be_a(BigDecimal)
    sample.btc.should be_a(BigDecimal)
    sample.btc_usd.should be_a(BigDecimal)
    sample.order_id.should be_a(Integer)
    sample.fee.should be_a(BigDecimal)
    sample.type.should be_a(Integer)
    sample.timestamp.should be_a(Integer)
  end

  it '#find_lost' do
    stub_bitstamp_orders

    sample = wrapper.orders.sample
    wrapper.find_lost(sample.type, sample.price, sample.amount).present?
  end
end
