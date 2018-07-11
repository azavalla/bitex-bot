require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(described_class.statuses)) }

  before(:each) { BitexBot::Robot.setup }

  let(:order_id) { 12_345 }
  let(:time_to_live) { 3 }
  let(:order_book) { bitstamp_api_wrapper_order_book }
  let(:transactions) { bitstamp_api_wrapper_transactions_stub }
  let(:maker_fee) { 0.5.to_d }
  let(:taker_fee) { 0.25.to_d }
  let(:store) { create(:store) }

  describe 'when creating a buying flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: time_to_live)
      stub_bitex_active_orders
    end

    let(:flow) do
      described_class.create_for_market(btc_balance, order_book.bids, transactions, maker_fee, taker_fee, store)
    end

    context 'with BTC balance 100' do
      let(:btc_balance) { 100.to_d }

      it 'order has expected order book' do
        order = described_class.order_class.find(flow.order_id)

        order.order_book.should eq BitexBot::Settings.maker_settings.order_book
      end

      it 'spends 50 usd' do
        amount_to_spend = 50.to_d
        usd_price = '19.85074626865672'.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0, fx_rate: 1))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq amount_to_spend
        flow.price.should <= flow.suggested_closing_price
      end

      context 'spends 100 usd' do
        before(:each) { BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0, fx_rate: 1)) }

        let(:amount_to_spend) { 100.to_d }
        let(:usd_price) { '14.888_059_701_492'.to_d }

        it 'with default fx_rate (1)' do
          flow.order_id.should eq order_id
          flow.value_to_use.should eq amount_to_spend
          flow.price.should <= flow.suggested_closing_price
        end

        it 'with other fx_rate' do
          other_fx_rate = 10.to_d
          BitexBot::Settings.buying.stub(fx_rate: other_fx_rate)

          flow.order_id.should eq order_id
          flow.value_to_use.should eq amount_to_spend
          flow.price.should <= flow.suggested_closing_price * other_fx_rate
        end
      end

      it 'lowers the price to pay on bitex to take a profit' do
        profit = 50.to_d
        amount_to_spend = 100.to_d
        usd_price = '7.44_402_985_074_627'.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: profit, fx_rate: 1))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq amount_to_spend
        flow.price.should <= flow.suggested_closing_price
      end

      it 'fails when there is a problem placing the bid on bitex' do
        amount_to_spend = 100.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0, fx_rate: 1))
        Bitex::Bid.stub(:create!) { raise StandardError, 'Cannot Create' }

        expect do
          flow.should be_nil
          described_class.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow, 'Cannot Create')
      end

      context 'with preloaded store' do
        let(:store) { create(:store, buying_profit: 0.5.to_d) }

        it 'prioritizes profit from it' do
          amount_to_spend = 50.to_d
          usd_price = '19.7514925373134'.to_d
          BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0, fx_rate: 1))

          flow.price.round(13).should eq usd_price
        end
      end

      it 'cancels the associated bitex bid' do
        amount_to_spend = 50.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0, fx_rate: 1))

        flow.finalise!.should be_truthy
        flow.should be_settling

        flow.finalise!.should be_truthy
        flow.should be_finalised
      end
    end

    context 'with BTC balance 1' do
      let(:btc_balance) { 1.to_d }

      it 'fails when there are not enough bitcoin to sell in the other exchange' do
        amount_to_spend = 100.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0, fx_rate: 1))

        expect do
          flow.should be_nil
          described_class.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow, 'Needed 6.716791979949874686733333333333333333 but you only have 1.0')
      end
    end
  end

  describe 'when fetching open positions' do
    before(:each) { stub_bitex_transactions }

    let(:flow) { create(:buy_opening_flow) }
    let(:trades) { described_class.sync_open_positions }
    let(:trade_id) { 12_345_678 }

    it 'only gets buys' do
      flow.order_id.should eq order_id

      expect do
        trades.size.should eq 1
        trades.sample.tap do |t|
          t.opening_flow.should eq flow
          t.transaction_id.should eq trade_id
          t.price.should eq 300.0
          t.amount.should eq 600.0
          t.quantity.should eq 2
        end
      end.to change { BitexBot::OpenBuy.count }.by(1)
    end

    it 'does not register the same buy twice' do
      flow.order_id.should eq order_id
      described_class.sync_open_positions

      BitexBot::OpenBuy.count.should eq 1

      Timecop.travel(1.second.from_now)
      trade_id = 23_456
      stub_bitex_transactions(build(:bitex_buy, id: trade_id))

      expect do
        trades.size.should eq 1
        trades.sample.transaction_id.should eq trade_id
      end.to change { BitexBot::OpenBuy.count }.by(1)
    end

    it 'does not register buys from another order book' do
      Bitex::Trade.stub(all: [build(:bitex_buy, id: 23_456, order_book: :btc_ars)])

      flow.order_id.should == 12345
      expect { described_class.sync_open_positions.should be_empty }.not_to change { BitexBot::OpenBuy.count }
      BitexBot::OpenBuy.count.should be_zero
    end

    it 'does not register buys from unknown bids' do
      expect { described_class.sync_open_positions.should be_empty }.not_to change { BitexBot::OpenBuy.count }
    end
  end
end
