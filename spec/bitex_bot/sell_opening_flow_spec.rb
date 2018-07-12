require 'spec_helper'

describe BitexBot::SellOpeningFlow do
  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(described_class.statuses)) }

  before(:each) { BitexBot::Robot.setup }

  let(:order_id) { 12_345 }
  let(:order_book) { bitstamp_api_wrapper_order_book.asks }
  let(:transactions) { bitstamp_api_wrapper_transactions_stub }
  let(:store) { create(:store) }

  describe 'when creating a selling flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: 3.to_d)
      stub_bitex_active_orders
    end

    let(:flow) do
      described_class.create_for_market(
        balance.to_d,
        order_book,
        transactions,
        0.5.to_d,
        0.25.to_d,
        store
      )
    end

    context 'with USD balance 1000' do
      let(:balance) { 1_000 }

      it { described_class.order_class.find(flow.order_id).order_book.should eq BitexBot::Settings.maker_settings.order_book }

      context 'with default fx_rate(1)' do
        before(:each) do
          BitexBot::Settings.stub(selling: build(:selling_settings, quantity_to_sell_per_order: quantity_to_sell.to_d, profit: 0, fx_rate: 1))
      end

        context 'sells 2 btc' do
          let(:quantity_to_sell) { 2 }

          it do
            flow.order_id.should eq order_id
            flow.value_to_use.should eq quantity_to_sell
            flow.price.should >= flow.suggested_closing_price
          end

          it 'cancels the associated bitex ask' do
            flow.finalise!.should be_truthy
            flow.should be_settling

            flow.finalise!.should be_truthy
            flow.should be_finalised
          end


          context 'with preloaded store' do
            let(:store) { create(:store, selling_profit: 0.5.to_d) }

            it 'prioritizes profit from it' do
              flow.order_id.should eq order_id
              flow.value_to_use.should eq quantity_to_sell
              flow.price.should >= flow.suggested_closing_price * BitexBot::Settings.buying.fx_rate
            end
          end
        end

        context 'sells 4 btc' do
          let(:quantity_to_sell) { 4 }

          it 'raises the price to charge on bitex to take a profit' do
            flow.order_id.should eq order_id
            flow.value_to_use.should eq quantity_to_sell
            flow.price.should >= flow.suggested_closing_price * BitexBot::Settings.buying.fx_rate
          end

          it 'fails when there is a problem placing the ask on bitex' do
            Bitex::Ask.stub(:create!) { raise StandardError, 'Cannot Create' }

            expect do
              flow.should be_nil
              described_class.count.should be_zero
            end.to raise_exception(BitexBot::CannotCreateFlow, 'Cannot Create')
          end

          context 'with other fx_rate' do
            let(:fx_rate) { 10 }

            it do
              flow.order_id.should eq order_id
              flow.value_to_use.should eq quantity_to_sell
              flow.price.should >= flow.suggested_closing_price * BitexBot::Settings.selling.fx_rate
            end
          end
        end
      end
    end

    context 'with USD balance 1' do
      let(:balance) { 1 }
      let(:quantity_to_sell) { 4 }

      it 'fails when there are not enough USD to re-buy in the other exchange' do
        BitexBot::Settings.stub(selling: build(:selling_settings, quantity_to_sell_per_order: quantity_to_sell.to_d))

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

        trades.sample.tap do |sample|
          sample.opening_flow.should eq flow
          sample.transaction_id.should eq trade_id
          sample.price.should eq 300
          sample.amount.should eq 600
          sample.quantity.should eq 2
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
      BitexBot::OpenSell.count.should be_zero
    end
  end
end
