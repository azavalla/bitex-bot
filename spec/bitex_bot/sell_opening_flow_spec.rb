require 'spec_helper'

describe BitexBot::SellOpeningFlow do
  it_behaves_like BitexBot::OpeningFlow

  before(:each) { BitexBot::Robot.setup }

  let(:order_id) { 12_345 }
  let(:order_book) { bitstamp_api_wrapper_order_book.asks }
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
        bitstamp_api_wrapper_transactions_stub,
        0.5.to_d,
        0.25.to_d,
        store
      )
    end

    def consistent_flow
      flow.order_id.should eq order_id
      flow.value_to_use.should eq quantity_to_sell
      flow.price.should >= flow.suggested_closing_price * BitexBot::Settings.selling.fx_rate
    end

    context 'with USD balance 1000' do
      let(:balance) { 1_000 }

      it { described_class.order_class.find(flow.order_id).order_book.should eq BitexBot::Settings.maker_settings.order_book }

      context 'with default fx_rate(1)' do
        before(:each) do
          BitexBot::Settings.stub(selling: build(:selling_settings, quantity_to_sell_per_order: quantity_to_sell.to_d, fx_rate: fx_rate.to_d))
        end

        let(:fx_rate) { 1 }

        context 'sells 2 btc' do
          let(:quantity_to_sell) { 2 }

          it { consistent_flow }

          it 'cancels the associated bitex ask' do
            flow.finalise!.should be_truthy
            flow.should be_settling

            flow.finalise!.should be_truthy
            flow.should be_finalised
          end

          context 'with preloaded store' do
            let(:store) { create(:store, selling_profit: 0.5.to_d) }

            it 'prioritizes profit from it' do
              consistent_flow
            end
          end
        end

        context 'sells 4 btc' do
          let(:quantity_to_sell) { 4 }

          it 'raises the price to charge on bitex to take a profit' do
            consistent_flow
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

            it { consistent_flow }
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
        end.to raise_exception(BitexBot::CannotCreateFlow)
        # Needed more than 1.0 but you only have 1.0
      end
    end
  end
end
