require 'spec_helper'

describe BitexBot::Api::Bitstamp do
  before(:each) do
    BitexBot::Settings.stub(taker: build(:bitstamp_taker))
    BitexBot::Robot.setup
  end

  let(:wrapper) { BitexBot::Robot.taker }
  let(:url) { 'https://www.bitstamp.net/api/v2/balance/btcusd/' }
  let(:stub_stuff) { stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent }) }
  let(:stuff_method) { :balance }
  let(:raw_order_classes) { [Bitstamp::Order] }
  let(:raw_transaction_classes) { [Bitstamp::Transactions] }

  it_behaves_like BitexBot::Api::Wrapper

  context '#place_order' do
    it 'raises OrderNotFound error on bitstamp errors' do
      Bitstamp.orders.stub(:buy) { raise BitexBot::Api::OrderNotFound }
      Bitstamp.orders.stub(:sell) { raise BitexBot::Api::OrderNotFound }

      expect { wrapper.place_order(:buy, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
      expect { wrapper.place_order(:sell, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
    end
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
end
