require 'spec_helper'

describe BitexBot::Api::Bitex do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitex: {
        api_key: 'taker_api_key', ssl_version: nil, debug: false, sandbox: false
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  let(:wrapper) { BitexBot::Robot.taker }
  let(:url) { "https://bitex.la/api-v1/rest/private/profile?api_key=#{wrapper.api_key}" }

  it 'Sends User-Agent header' do
    stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    expect { wrapper.balance }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end

  it '#balance' do
    stub_bitex_balance

    balance = wrapper.balance
    balance.should be_a(BitexBot::Api::BalanceSummary)
    balance.members.should contain_exactly(*%i[btc usd fee])

    balance.btc.should be_a(BitexBot::Api::Balance)
    balance.usd.should be_a(BitexBot::Api::Balance)
    balance.fee.should be_a(BigDecimal)

    [balance.btc, balance.usd].all? do |sample|
      sample.members.should contain_exactly(*%i[total reserved available])

      sample.total.should be_a(BigDecimal)
      sample.reserved.should be_a(BigDecimal)
      sample.available.should be_a(BigDecimal)
    end
  end

  it '#cancel' do
    stub_bitex_orders

    wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_bitex_order_book

    order_book = wrapper.order_book
    order_book.should be_a(BitexBot::Api::OrderBook)
    order_book.members.should contain_exactly(*%i[bids asks timestamp])

    order_book.bids.should be_a(Array)
    order_book.asks.should be_a(Array)
    order_book.timestamp.should be_a(Integer)

    [order_book.bids.sample, order_book.asks.sample].all? do |sample|
      sample.should be_a(BitexBot::Api::OrderSummary)
      sample.members.should contain_exactly(*%i[price quantity])

      sample.price.should be_a(BigDecimal)
      sample.quantity.should be_a(BigDecimal)
    end
  end

  it '#orders' do
    stub_bitex_orders

    wrapper.orders.should be_a(Array)

    sample = wrapper.orders.sample
    sample.should be_a(BitexBot::Api::Order)
    sample.members.should contain_exactly(*%i[id type price amount timestamp raw])

    sample.id.should be_a(String)
    sample.type.should be_a(Symbol)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    [Bitex::Ask, Bitex::Bid].should include(sample.raw.class)
  end

  context '#place_order' do
    it 'raises OrderNotFound error on Bitex errors' do
      Bitex::Bid.stub(create!: nil)
      Bitex::Ask.stub(create!: nil)
      wrapper.stub(find_lost: nil)

      expect { wrapper.place_order(:buy, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
      expect { wrapper.place_order(:sell, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
    end
  end

  it '#transactions' do
    stub_bitex_transactions

    wrapper.transactions.should be_a(Array)

    sample = wrapper.transactions.sample
    sample.should be_a(BitexBot::Api::Transaction)
    sample.members.should contain_exactly(*%i[id price amount timestamp raw])

    sample.id.should be_a(Integer)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    [Bitex::Sell, Bitex::Buy].should include(sample.raw.class)
  end

  it '#user_transaction' do
    stub_bitex_trades

    wrapper.user_transactions.should be_a(Array)

    sample = wrapper.user_transactions.sample
    sample.should be_a(BitexBot::Api::UserTransaction)
    sample.members.should contain_exactly(*%i[order_id usd btc btc_usd fee type timestamp])

    sample.order_id.should be_a(Integer)
    sample.usd.should be_a(BigDecimal)
    sample.btc.should be_a(BigDecimal)
    sample.btc_usd.should be_a(BigDecimal)
    sample.fee.should be_a(BigDecimal)
    sample.type.should be_a(Integer)
    sample.timestamp.should be_a(Integer)
  end

  it '#find_lost' do
    stub_bitex_orders

    sample = wrapper.orders.sample
    wrapper.find_lost(sample.type, sample.price, sample.amount).present?
  end
end
