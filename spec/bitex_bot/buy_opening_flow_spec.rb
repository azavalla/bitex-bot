require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  before(:each) { BitexBot::Robot.setup }

  it_behaves_like BitexBot::OpeningFlow

  describe '#create for market' do
    let(:taker_orders) { bitstamp_api_wrapper_order_book.bids }
    let(:taker_transactions) { bitstamp_api_wrapper_transactions_stub }
    let(:maker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:taker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:store) { create(:store) }

    let(:flow) { described_class.create_for_market(taker_balance, taker_orders, taker_transactions, maker_fee, taker_fee, store) }

    context 'the external value remote calculated gives 2 approximately' do
      context 'when taker balance is greater or equal than remote value, that later it will be used to calculate bitex price' do
        before(:each) { described_class.order_class.stub(create!: order) }

        let(:order) { build(:bitex_bid) }
        let(:taker_balance) { Faker::Number.normal(100, 10).truncate(2).to_d }

        context 'success' do
          let(:fx_rate) { BitexBot::Settings.buying.fx_rate }

          it { flow.order_id.should eq order.id }
          it { flow.should be_a(described_class) }
          it { flow.price.should <= flow.suggested_closing_price * fx_rate }
        end

        context 'fails, when try place order on maker, but you do not have sufficient funds' do
          let(:value_to_use) { BitexBot::Settings.buying.amount_to_spend_per_order }
          let(:order) { build(:bitex_bid, reason: :not_enough_funds) }
          let(:error) { "You need to have #{value_to_use} on bitex to place this Bitex::Bid." }

          it { expect { flow }.to raise_exception(BitexBot::CannotCreateFlow, error) }
        end

        context 'fails, when creating  any validation' do
          before(:each) { described_class.stub(:create!) { raise error } }

          let(:error) { StandardError }

          it { expect { flow }.to raise_exception(BitexBot::CannotCreateFlow, error.to_s) }
        end
      end

      context 'fails, when taker balance is lower than remote value' do
        before(:each) { described_class.store = store }

        let(:needed) { described_class.calc_remote_value(maker_fee, taker_fee, taker_orders, taker_transactions)[0] }
        let(:taker_balance) { needed - 1 }
        let(:error) { "Needed #{needed} but you only have #{taker_balance}" }

        it { expect { flow }.to raise_exception(BitexBot::CannotCreateFlow, error) }
      end
    end
  end

=begin
  describe '#transaction order id' do
    let(:trade) { build(:bitex_buy) }
    let(:transaction) { BitexBot::Api::Transaction.new(trade.id, trade.price, trade.amount, trade.created_at.to_i, trade) }

    it { described_class.transaction_order_id(transaction).should eq trade.bid_id }
  end

  describe '#open position class' do
    it { described_class.open_position_class.should eq BitexBot::OpenBuy }
  end

  describe '#transaction class' do
    it { described_class.transaction_class.should eq Bitex::Buy }
  end


#  before(:each) { BitexBot::Robot.setup }

#  let(:order_id) { 12_345 }
#  let(:order_book) { bitstamp_api_wrapper_order_book.bids }
#  let(:store) { create(:store) }

  describe 'when creating a buying flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: 3.to_d)
      stub_bitex_active_orders
    end

    let(:flow) do
      described_class.create_for_market(
        balance.to_d,
        order_book,
        bitstamp_api_wrapper_transactions_stub,
        0.5.to_d,
        0.25.to_d,
        store
      )
    end

    def consistent_flow
      flow.order_id.should eq order_id
      flow.value_to_use.should eq amount_to_spend
      flow.price.should <= flow.suggested_closing_price * BitexBot::Settings.buying.fx_rate
    end

    context 'with BTC balance 100' do
      let(:balance) { 100 }

      it { described_class.order_class.find(flow.order_id).order_book.should eq BitexBot::Settings.maker_settings.order_book }

      context 'with default fx_rate(1)' do
        before(:each) do
          BitexBot::Settings.stub(buying: build(:buying_settings, amount_to_spend_per_order: amount_to_spend.to_d, fx_rate: fx_rate.to_d))
        end

        let(:fx_rate) { 1 }

        context 'spends 50 usd' do
          let(:amount_to_spend) { 50 }

          it { consistent_flow }

          it 'cancels the associated bitex bid' do
            flow.finalise!.should be_truthy
            flow.should be_settling

            flow.finalise!.should be_truthy
            flow.should be_finalised
          end

          context 'with preloaded store' do
            let(:store) { create(:store, buying_profit: 0.5.to_d) }

            it 'prioritizes profit from it' do
              consistent_flow
            end
          end
        end

        context 'spends 100 usd' do
          let(:amount_to_spend) { 100 }

          it 'lowers the price to pay on bitex to take a profit' do
            consistent_flow
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

            it { consistent_flow }
          end
        end
      end
    end

    context 'with BTC balance 1' do
      let(:balance) { 1 }
      let(:amount_to_spend) { 100 }

      it 'fails when there are not enough bitcoin to sell in the other exchange' do
        BitexBot::Settings.stub(buying: build(:buying_settings, amount_to_spend_per_order: amount_to_spend.to_d))

        expect do
          flow.should be_nil
          described_class.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow)
        # Needed more than 1.0 but you only have 1.0
      end
    end
  end
=end
end
