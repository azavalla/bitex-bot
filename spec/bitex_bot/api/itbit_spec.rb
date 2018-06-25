require 'spec_helper'

describe BitexBot::Api::Itbit do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      itbit: {
        client_key: 'client-key', secret: 'secret', user_id: 'user-id',  default_wallet_id: 'wallet-000', sandbox: false
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  let(:wrapper) { BitexBot::Robot.taker }
  let(:url) { "https://api.itbit.com/v1/wallets?userId=#{wrapper.user_id}" }

  it 'Sends User-Agent header' do
    stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # We don't care about the response
    expect { wrapper.balance }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end

  it '#balance' do
    stub_itbit_balance

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
    stub_itbit_orders

    wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_itbit_order_book

    order_book = wrapper.order_book
    order_book.should be_a(BitexBot::Api::OrderBook)
    order_book.members.should contain_exactly(*%i[bids asks timestamp])

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
    stub_itbit_orders

    wrapper.orders.should be_a(Array)

    sample = wrapper.orders.sample
    sample.should be_a(BitexBot::Api::Order)
    sample.members.should contain_exactly(*%i[id type price amount timestamp raw])

    sample.id.should be_a(String)
    sample.type.should be_a(Symbol)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    sample.raw.should be_a(Itbit::Order)
  end

  context '#place_order' do
    before(:each) { Itbit::Order.stub(:create!) { raise error } }

    def with_founded(type, price, amount)
      yield
      wrapper.place_order(type, price, amount).should be_present
    end

    def with_error(type, price, amount)
      yield
      expect { wrapper.place_order(type, price, amount) }.to raise_exception(error)
    end

    context 'raises time out error' do
      let(:error) { RestClient::RequestTimeout }

      it { with_founded(:buy, 2.5, 100) { stub_itbit_orders } }
      it { with_founded(:sell, 2.5, 100) { stub_itbit_orders } }
      it { with_error(:buy, 2.5, 100) { Itbit::Order.stub(all: []) } }
      it { with_error(:sell, 2.5, 100) { Itbit::Order.stub(all: []) } }
    end

    context 'another error kind aren´t handled' do
      let(:error) { StandardError }

      it { with_error(:buy, 2.5, 100) { Itbit::Order.stub(all: []) } }
      it { with_error(:sell, 2.5, 100) { Itbit::Order.stub(all: []) } }
    end
  end

  it '#transactions' do
    stub_itbit_transactions

    wrapper.transactions.should be_a(Array)

    sample = wrapper.transactions.sample
    sample.should be_a(BitexBot::Api::Transaction)
    sample.members.should contain_exactly(*%i[id price amount timestamp raw])

    sample.id.should be_a(Integer)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    sample.raw.should be_a(Hash)
    sample.raw.keys.should contain_exactly(*%i[tid price amount date])
  end

  it '#user_transaction' do
    wrapper.user_transactions.should be_a(Array)
    wrapper.user_transactions.empty?.should be_truthy
  end

  it '#find_lost' do
    stub_itbit_orders

    sample = wrapper.orders.sample
    wrapper.find_lost(sample.type, sample.price, sample.amount).present?
  end
end
