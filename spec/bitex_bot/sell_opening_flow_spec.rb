require 'spec_helper'

describe BitexBot::SellOpeningFlow do
  before(:each) { BitexBot::Robot.setup }

  it_behaves_like BitexBot::OpeningFlow

  describe '#create for market' do
    let(:taker_orders) { bitstamp_api_wrapper_order_book.asks }
    let(:taker_transactions) { bitstamp_api_wrapper_transactions_stub }
    let(:maker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:taker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:store) { create(:store) }

    let(:flow) { described_class.create_for_market(taker_balance, taker_orders, taker_transactions, maker_fee, taker_fee, store) }

    context 'the external value remote calculated gives 2 approximately' do
      context 'when taker balance is greater or equal than remote value, that later it will be used to calculate bitex price' do
        before(:each) { described_class.order_class.stub(create!: order) }

        let(:order) { build(:bitex_ask) }
        let(:taker_balance) { Faker::Number.normal(100, 10).truncate(2).to_d }

        context 'success' do
          let(:fx_rate) { BitexBot::Settings.selling.fx_rate }

          it { flow.order_id.should eq order.id }
          it { flow.should be_a(described_class) }
          it { flow.price.should >= flow.suggested_closing_price * fx_rate }
        end

        context 'fails, when try place order on maker, but you do not have sufficient funds' do
          let(:value_to_use) { BitexBot::Settings.selling.quantity_to_sell_per_order }
          let(:order) { build(:bitex_ask, reason: :not_enough_funds) }
          let(:error) { "You need to have #{value_to_use} on bitex to place this Bitex::Ask." }

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
  #let(:order_id) { 12_345 }
  #let(:order_book) { bitex_api_wrapper_order_book.asks }
  #let(:store) { create(:store) }

  describe '#transaction order id' do
    let(:trade) { build(:bitex_sell) }
    let(:transaction) { BitexBot::Api::Transaction.new(trade.id, trade.price, trade.amount, trade.created_at.to_i, trade) }

    it { described_class.transaction_order_id(transaction).should eq trade.ask_id }
  end

  describe '#open position class' do
    it { described_class.open_position_class.should eq BitexBot::OpenSell }
  end

  describe '#transaction class' do
    it { described_class.transaction_class.should eq Bitex::Sell }
  end

  describe '#maker price' do
    before(:each) { described_class.store = store }
    let(:fiat_to_spend_re_buying) { Faker::Number.normal(50, 10).truncate(2) }

    # obtained factor with profit: 0.5, value_to_use: 0.1, and fx_rate: 1.0
    let(:percentile_factor) { 10.05.to_d }

    it { described_class.maker_price(fiat_to_spend_re_buying).should eq fiat_to_spend_re_buying * percentile_factor }
  end

  describe '#order class' do
    it { described_class.order_class.should eq Bitex::Ask }
  end

  describe '#profit' do
    let(:profit) { Faker::Number.normal(40, 10).truncate(2).to_d }

    context 'with created store' do
      before(:each) do
        described_class.store = build(:store)
        BitexBot::SettingsClass.any_instance.stub(selling: build(:selling_settings, profit: profit))
      end

      it 'with nil selling_profit' do
        described_class.profit.should eq profit
      end
    end

    context 'with a loaded store' do
      before(:each) { described_class.store = build(:store, selling_profit: profit)  }

      it { described_class.profit.should eq profit }
    end
  end

  describe '#remote value to use' do
    let(:value) { Faker::Number.normal(40, 10).truncate(2).to_d }
    let(:price) { Faker::Number.normal(40, 10).truncate(2).to_d }

    it { described_class.remote_value_to_use(value, price).should eq value * price }
  end

  # HOW FUCK TEST IT?
  describe '#safest price' do
    let(:taker_transactions) { bitstamp_api_wrapper_transactions_stub }
    let(:crypto_to_use) { Faker::Number.normal(15, 1).truncate(2).to_d }

    it 'is indifferent about crypto to use' do
      described_class.safest_price(taker_transactions, order_book, crypto_to_use).should eq 30
    end
  end

  describe '#value to use' do
    let(:profit) { Faker::Number.normal(40, 10).truncate(2).to_d }
    let(:error_message) { "undefined method `selling_quantity_to_sell_per_order' for nil:NilClass" }

    it 'without store' do
      described_class.store = nil
      expect { described_class.value_to_use }.to raise_exception(NoMethodError, error_message)
    end

    context 'with created store' do
      before(:each) { described_class.store = build(:store, selling_profit: profit)  }
      context 'and empty selling_profit' do
        before(:each) do
          described_class.store = store
          BitexBot::SettingsClass.any_instance.stub(selling: build(:selling_settings, profit: profit))
        end

        it  do
          described_class.profit.should eq profit
        end
      end

      context 'and loaded selling_profit' do
        before(:each) { described_class.store = build(:store, selling_profit: profit)  }

        it { described_class.profit.should eq profit }
      end
    end
  end

  describe '#fx rate' do
    before(:each) { BitexBot::SettingsClass.any_instance.stub(selling: build(:selling_settings, fx_rate: fx_rate)) }

    let(:fx_rate) { Faker::Number.normal(40, 10).truncate(2).to_d }

    it { described_class.fx_rate.should eq fx_rate }
  end

  describe 'when creating a selling flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: 3.to_d)
      stub_bitex_active_orders
    end

    let(:flow) do
      described_class.create_for_market(
        balance.to_d,
        order_book,
        bitex_api_wrapper_transactions_stub,
        0.5.to_d,
        0.25.to_d,
        store
      )
    end

    def successfull_flow
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

          it { successfull_flow }

          it 'cancels the associated bitex ask' do
            flow.finalise!.should be_truthy
            flow.should be_settling

            flow.finalise!.should be_truthy
            flow.should be_finalised
          end

          context 'with preloaded store' do
            let(:store) { create(:store, selling_profit: 0.5.to_d) }

            it 'prioritizes profit from it' do
              successfull_flow
            end
          end
        end

        context 'sells 4 btc' do
          let(:quantity_to_sell) { 4 }

          it 'raises the price to charge on bitex to take a profit' do
            successfull_flow
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

            it { successfull_flow }
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
=end
end
