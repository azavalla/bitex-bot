require 'spec_helper'

describe BitexBot::Api::Kraken do
  before(:each) do
    BitexBot::Settings.stub(taker: build(:kraken_taker))
    BitexBot::Robot.setup
  end

  let(:wrapper) { BitexBot::Robot.taker }
  let(:url) { 'https://api.kraken.com/0/public/Depth?pair=XBTUSD' }
  let(:stub_stuff) { stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent }) }
  let(:stuff_method) { :order_book  }
  let(:raw_order_classes) { [BitexBot::Api::Kraken::Order] }
  let(:raw_transaction_classes) { [Array] }

  it_behaves_like BitexBot::Api::Wrapper

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

  it '#user_transaction' do
    wrapper.user_transactions.should be_a(Array)
    wrapper.user_transactions.empty?.should be_truthy
  end
end
