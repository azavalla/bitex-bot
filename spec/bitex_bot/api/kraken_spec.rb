require 'spec_helper'

describe BitexBot::Api::Kraken do
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

  let(:wrapper) { BitexBot::Robot.taker }
  let(:url) { 'https://api.kraken.com/0/public/Depth?pair=XBTUSD' }

  it 'Sends User-Agent header' do
    stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # We don't care about the response
    expect { wrapper.order_book }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end

  it '#balance' do
    stub_kraken_private_client
    stub_kraken_orders
    stub_kraken_balance
    stub_kraken_trade_volume

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
    stub_kraken_private_client
    stub_kraken_orders

    wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_kraken_public_client
    stub_kraken_order_book

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
    stub_kraken_private_client
    stub_kraken_orders

    wrapper.orders.should be_a(Array)

    sample = wrapper.orders.sample
    sample.should be_a(BitexBot::Api::Order)
    sample.members.should contain_exactly(*%i[id type price amount timestamp raw])

    sample.id.should be_a(String)
    sample.type.should be_a(Symbol)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    sample.raw.should be_a(described_class::Order)
  end

  context '#place_order' do
    it 'raises OrderNotFound error on Bitex errors' do
      described_class::Order.stub(create!: nil)
      wrapper.stub(find_lost: nil)

      expect { wrapper.place_order(:buy, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
      expect { wrapper.place_order(:sell, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
    end
  end

  context '#send_order' do
    before(:each) do
      described_class::Order.stub(closed: [])
    end

    def with_founded(type, price, quantity)
      yield
      wrapper.place_order(type, price, quantity).should be_present
    end

    def with_error(type, price, quantity)
      yield
      expect { wrapper.place_order(type, price, quantity) }.to raise_exception(error, message)
    end

    context 'raises' do
      let(:client_error) { KrakenClient::ErrorResponse }

      def with_retries(retries)
        described_class::Order.stub(:order_info_by) do
          if retries.zero?
            retries += 1
            raise client_error, client_message
          end
          raise error
        end
      end

      context 'recovers from EService:Unavailable client error, then retries raise another error' do
        let(:error) { StandardError }
        let(:message) { }
        let(:client_message) { 'EService:Unavailable' }

        it { with_error(:buy, 2.5, 100) { with_retries(0) } }
        it { with_error(:sell, 2.5, 100) { with_retries(0) } }
      end

      context 'recovers from EGeneral:Invalid client error and forward to custom error' do
        let(:error) { BitexBot::Api::OrderArgumentError }
        let(:message) { client_message }
        let(:client_message) { 'EGeneral:Invalid' }

        it { with_error(:buy, 2.5, 100) { with_retries(0) } }
        it { with_error(:sell, 2.5, 100) { with_retries(0) } }
      end

      context 'recovers from another KrakenClient::ErrorResponse message' do
        let(:error) { StandardError }
        let(:message) { }
        let(:client_message) { 'notsobadda' }

        it { with_error(:buy, 2.5, 100) { with_retries(0) } }
        it { with_error(:sell, 2.5, 100) { with_retries(0) } }
      end
    end
  end

  it '#transactions' do
    stub_kraken_public_client
    stub_kraken_transactions

    wrapper.transactions.should be_a(Array)

    sample = wrapper.transactions.sample
    sample.should be_a(BitexBot::Api::Transaction)
    sample.members.should contain_exactly(*%i[id price amount timestamp raw])

    sample.id.should be_a(Integer)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    sample.raw.should be_a(Array)
  end

  it '#user_transaction' do
    wrapper.user_transactions.should be_a(Array)
    wrapper.user_transactions.empty?.should be_truthy
  end

  it '#find_lost' do
    stub_kraken_private_client
    stub_kraken_orders

    sample = wrapper.orders.sample
    wrapper.find_lost(sample.type, sample.price, sample.amount).present?
  end
end
