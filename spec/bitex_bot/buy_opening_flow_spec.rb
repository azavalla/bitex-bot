require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(described_class.statuses)) }

  before(:each) { BitexBot::Robot.setup }

  let(:order_id) { 12_345 }
  let(:store) { create(:store) }

  describe 'when creating a buying flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: 3.to_d)
      stub_bitex_active_orders
    end

    let(:flow) do
      described_class.create_for_market(
        btc_balance.to_d,
        bitstamp_api_wrapper_order_book.bids,
        bitstamp_api_wrapper_transactions_stub,
        0.5.to_d,
        0.25.to_d,
        store
      )
    end

    context 'with BTC balance 100' do
      let(:btc_balance) { 100 }

      it { described_class.order_class.find(flow.order_id).order_book.should eq BitexBot::Settings.maker_settings.order_book }

      context 'with default fx_rate(1)' do
        before(:each) do
          BitexBot::Settings.stub(buying: build(:buying_settings, amount_to_spend_per_order: amount_to_spend.to_d, fx_rate: fx_rate.to_d))
        end

        let(:fx_rate) { 1 }

        context 'spends 50 usd' do
          let(:amount_to_spend) { 50 }

          it do
            flow.order_id.should eq order_id
            flow.value_to_use.should eq amount_to_spend
            flow.price.should <= flow.suggested_closing_price * BitexBot::Settings.buying.fx_rate
          end

          it 'cancels the associated bitex bid' do
            flow.finalise!.should be_truthy
            flow.should be_settling

            flow.finalise!.should be_truthy
            flow.should be_finalised
          end

          context 'with preloaded store' do
            let(:store) { create(:store, buying_profit: 0.5.to_d) }

            it 'prioritizes profit from it' do
              flow.order_id.should eq order_id
              flow.value_to_use.should eq amount_to_spend
              flow.price.should <= flow.suggested_closing_price * BitexBot::Settings.buying.fx_rate
            end
          end
        end

        context 'spends 100 usd' do
          let(:amount_to_spend) { 100 }

          it 'lowers the price to pay on bitex to take a profit' do
            flow.order_id.should eq order_id
            flow.value_to_use.should eq amount_to_spend
            flow.price.should <= flow.suggested_closing_price * BitexBot::Settings.buying.fx_rate
          end

          it 'fails when there is a problem placing the bid on bitex' do
            Bitex::Bid.stub(:create!) { raise StandardError, 'Cannot Create' }

            expect do
              flow.should be_nil
              described_class.count.should be_zero
            end.to raise_exception(BitexBot::CannotCreateFlow, 'Cannot Create')
          end

          context 'with other fx_rate' do
            let(:fx_rate) { 10 }

            it do
              flow.order_id.should eq order_id
              flow.value_to_use.should eq amount_to_spend
              flow.price.should <= flow.suggested_closing_price * BitexBot::Settings.buying.fx_rate
            end
          end
        end
      end
    end

    context 'with BTC balance 1' do
      let(:btc_balance) { 1 }
      let(:amount_to_spend) { 100 }

      it 'fails when there are not enough bitcoin to sell in the other exchange' do
        BitexBot::Settings.stub(buying: build(:buying_settings, amount_to_spend_per_order: amount_to_spend))

        expect do
          flow.should be_nil
          described_class.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow)
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

        trades.sample.tap do |sample|
          sample.opening_flow.should eq flow
          sample.transaction_id.should eq trade_id
          sample.price.should eq 300.0
          sample.amount.should eq 600.0
          sample.quantity.should eq 2
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

      expect { described_class.sync_open_positions.should be_empty }.not_to change { BitexBot::OpenBuy.count }
      BitexBot::OpenBuy.count.should be_zero
    end

    it 'does not register buys from unknown bids' do
      expect { described_class.sync_open_positions.should be_empty }.not_to change { BitexBot::OpenBuy.count }
      BitexBot::OpenBuy.count.should be_zero
    end
  end
end
