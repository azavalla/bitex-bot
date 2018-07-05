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
  let(:stub_stuff) { stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent }) }
  let(:stuff_method) { :balance }
  let(:raw_order_classes) { [Itbit::Order] }
  let(:raw_transaction_classes) { [Hash] }

  it_behaves_like BitexBot::Api::Wrapper

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

  it '#user_transaction' do
    wrapper.user_transactions.should be_a(Array)
    wrapper.user_transactions.empty?.should be_truthy
  end
end
