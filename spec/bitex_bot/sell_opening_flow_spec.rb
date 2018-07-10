require 'spec_helper'

describe BitexBot::SellOpeningFlow do
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
  let(:store) { BitexBot::Store.create }

  describe 'when creating a selling flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: time_to_live)
      stub_bitex_active_orders
    end

    let(:flow) { described_class.create_for_market(usd_balance, order_book.asks, transactions, maker_fee, taker_fee, store) }

    context 'with USD balance 1000' do
      let(:usd_balance) { 1_000.to_d }

      it 'order has expected order book' do
        order = described_class.order_class.find(flow.order_id)

        order.order_book.should eq BitexBot::Settings.maker_settings.order_book
      end

      it 'sells 2 btc' do
        quantity_to_sell = 2.to_d
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0, fx_rate: 1))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq quantity_to_sell
        flow.price.should >= flow.suggested_closing_price
      end

      context 'sells 4 btc' do
        before(:each) { BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0, fx_rate: 1)) }

        let(:quantity_to_sell) { 4.to_d }

        it 'with default fx_rate (1)' do
          flow.order_id.should eq order_id
          flow.value_to_use.should eq quantity_to_sell
          flow.price.should >= flow.suggested_closing_price
        end

        it 'with other fx_rate' do
          other_fx_rate = 10.to_d
          BitexBot::Settings.stub(selling_fx_rate: other_fx_rate)

          flow.order_id.should eq order_id
          flow.value_to_use.should eq quantity_to_sell
          flow.price.should >= flow.suggested_closing_price
        end
      end

      it 'raises the price to charge on bitex to take a profit' do
        quantity_to_sell = 4.to_d
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 50.to_d, fx_rate: 1))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq quantity_to_sell
        flow.price.should >= flow.suggested_closing_price
      end

      it 'fails when there is a problem placing the ask on bitex' do
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: 4, profit: 0, fx_rate: 1))
        Bitex::Ask.stub(:create!) { raise StandardError, 'Cannot Create' }

        expect do
          flow.should be_nil
          described_class.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow, 'Cannot Create')
      end

      context 'with preloaded store' do
        let(:store) { BitexBot::Store.new(selling_profit: 0.5) }

        it 'Prioritizes profit from it' do
          usd_price = '20.25_112_781_954_887'.to_d
          BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: 2, profit: 0, fx_rate: 1))

          flow.price.round(14).should eq usd_price
        end
      end

      it 'cancels the associated bitex ask' do
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: 2, profit: 0, fx_rate: 1))

        flow.finalise!.should be_truthy
        flow.should be_settling

        flow.finalise!.should be_truthy
        flow.should be_finalised
      end
    end

    context 'with USD balance 1' do
      let(:usd_balance) { 1.to_d }

      it 'fails when there are not enough USD to re-buy in the other exchange' do
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: 4, profit: 0, fx_rate: 1))

        expect do
          flow.should be_nil
          described_class.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow, 'Needed 100.7518796992481203 but you only have 1.0')
      end
    end
  end

  describe 'when fetching open positions' do
    before(:each) { stub_bitex_transactions }

    let(:flow) { create(:sell_opening_flow) }
    let(:trades) { described_class.sync_open_positions }
    let(:trade_id) { 12_345_678 }
    let(:other_trade_id) { 23_456 }

    it 'only gets sells' do
      flow.order_id.should eq order_id

      expect do
        trades.size.should eq 1

        trades.sample.tap do |t|
          t.opening_flow.should eq flow
          t.transaction_id.should eq trade_id
          t.price.should eq 300
          t.amount.should eq 600
          t.quantity.should eq 2
        end
      end.to change { BitexBot::OpenSell.count }.by(1)
    end

    it 'does not register the same buy twice' do
      flow.order_id.should eq order_id
      described_class.sync_open_positions

      BitexBot::OpenSell.count.should eq 1

      Timecop.travel(1.second.from_now)
      stub_bitex_transactions(build(:bitex_sell, id: other_trade_id))

      expect do
        trades.size.should eq 1
        trades.sample.transaction_id.should eq other_trade_id
      end.to change { BitexBot::OpenSell.count }.by(1)
    end

    it 'does not register buys from another order book' do
      Bitex::Trade.stub(all: [build(:bitex_sell, id: other_trade_id, order_book: :btc_ars)])

      expect { described_class.sync_open_positions.should be_empty }.not_to change { BitexBot::OpenSell.count }
      BitexBot::OpenSell.count.should be_zero
    end

    it 'does not register buys from unknown bids' do
      expect { described_class.sync_open_positions.should be_empty }.not_to change { BitexBot::OpenSell.count }
    end
  end
end
