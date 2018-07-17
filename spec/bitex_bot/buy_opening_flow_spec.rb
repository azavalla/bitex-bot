require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  it_behaves_like BitexBot::OpeningFlow

  before(:each) { BitexBot::Robot.setup }

  let(:order_id) { 12_345 }
  let(:order_book) { bitstamp_api_wrapper_order_book.bids }
  let(:store) { create(:store) }

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
end
