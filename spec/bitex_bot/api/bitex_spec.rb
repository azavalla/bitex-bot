require 'spec_helper'

describe BitexBot::Api::Bitex do
  before(:each) do
    BitexBot::Settings.stub(taker: build(:bitex_taker))
    BitexBot::Robot.setup
  end

  let(:wrapper) { BitexBot::Robot.taker }
  let(:url) { "https://bitex.la/api-v1/rest/private/profile?api_key=#{wrapper.api_key}" }
  let(:stub_stuff) { stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent }) }
  let(:stuff_method) { :balance }
  let(:raw_order_classes) { [Bitex::Ask, Bitex::Bid] }
  let(:raw_transaction_classes) { [Bitex::Sell, Bitex::Buy] }

  it_behaves_like BitexBot::Api::Wrapper

  context '#place_order' do
    it 'raises OrderNotFound error on Bitex errors' do
      Bitex::Bid.stub(create!: nil)
      Bitex::Ask.stub(create!: nil)
      wrapper.stub(find_lost: nil)

      expect { wrapper.place_order(:buy, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
      expect { wrapper.place_order(:sell, 10, 100) }.to raise_exception(BitexBot::Api::OrderNotFound)
    end
  end

  it '#user_transaction' do
    send("stub_bitex_trades")

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

  describe 'with Asks and Bids' do
    let(:order_name) { %i[bid ask].sample }
    let(:order_class) { "Bitex::#{order_name.capitalize}".constantize }

    describe '#find' do
      before(:each) { order_class.stub(find: order) }

      let(:order) { build(:"bitex_#{order_name}", id: order_id) }
      let(:order_id) { Faker::Number.between(100, 1_000) }

      subject { wrapper.find(order_class, order_id) }

      it do
        order_class.should receive(:find).with(order_id)
        subject.should eq order
      end
    end

    describe '#cancel' do
      before(:each) { order.stub(:cancel!) { order.tap { order.status = :cancelling } } }

      let(:order) { build(:"bitex_#{order_name}") }

      subject { wrapper.cancel(order) }

      it do
        order.should receive(:cancel!)
        subject.should eq order
        order.status.should eq :cancelling
      end
    end
  end
end
