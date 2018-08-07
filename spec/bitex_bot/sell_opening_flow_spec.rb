require 'spec_helper'

describe BitexBot::SellOpeningFlow do
  it_behaves_like BitexBot::OpeningFlow

  describe '#create for market' do
    subject { described_class.create_for_market(taker_balance, taker_orders, taker_transactions, maker_fee, taker_fee, store) }

    before(:each) { BitexBot::Robot.setup }

    let(:taker_orders) { bitstamp_api_wrapper_order_book.asks }
    let(:taker_transactions) { bitstamp_api_wrapper_transactions_stub }
    let(:maker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:taker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:store) { create(:store) }

    context 'the external value remote calculated gives 2 approximately' do
      context 'when taker balance is greater or equal than remote value, that later it will be used to calculate bitex price' do
        before(:each) { described_class.order_class.stub(create!: order) }

        let(:order) { build(:bitex_ask) }
        let(:taker_balance) { Faker::Number.normal(1_000, 10).truncate(2).to_d }

        it_behaves_like 'fails, when creating any validation'
        it_behaves_like 'fails, when try place order on maker, but you do not have sufficient funds'

        it 'success' do
          subject.should be_a(described_class)
          subject.order_id.should eq order.id
          subject.price.should >= subject.suggested_closing_price * described_class.fx_rate
        end
      end

      context 'fails, when there are not enough USD to re-buy in the other exchange' do
        before(:each) { described_class.store = store }

        let(:needed) { described_class.calc_remote_value(maker_fee, taker_fee, taker_orders, taker_transactions)[0] }
        let(:taker_balance) { needed - 1 }
        let(:error) { "Needed #{needed} but you only have #{taker_balance}" }

        it 'when taker balance is lower than remote value' do
          expect do
            subject.should be_nil
            described_class.count.should be_zero
          end.to raise_exception(BitexBot::CannotCreateFlow, error)
        end
      end
    end
  end

  describe '#transaction order id' do
    subject { described_class.transaction_order_id(transaction) }

    let(:trade) { build(:bitex_sell) }
    let(:transaction) { BitexBot::Api::Transaction.new(trade.id, trade.price, trade.amount, trade.created_at.to_i, trade) }

    it { should eq trade.ask_id }
  end

  describe '#open position class' do
    it { described_class.open_position_class.should eq BitexBot::OpenSell }
  end

  describe '#transaction class' do
    it { described_class.transaction_class.should eq Bitex::Sell }
  end

  describe '#maker price' do
    subject { described_class.maker_price(fiat_to_spend_re_buying) }

    before(:each) do
      described_class.store = create(:store)

      # it's not indifferent here, but yes on buy opening flow.
      described_class.stub(value_to_use: value_to_use)
      described_class.stub(fx_rate: fx_rate)
      described_class.stub(profit: profit)
    end

    let(:value_to_use) { Faker::Number.normal(50, 10).truncate(2) }
    let(:fx_rate) { Faker::Number.normal(50, 10).truncate(2) }
    let(:profit) { Faker::Number.normal(50, 10).truncate(2) }

    let(:fiat_to_spend_re_buying) { Faker::Number.normal(50, 10).truncate(2) }

    let(:source_amount) { fiat_to_spend_re_buying * fx_rate }
    let(:percentile_profit) { 1 + profit / 100 }

    it { should eq source_amount / value_to_use * percentile_profit }
  end

  describe '#order class' do
    it { described_class.order_class.should eq Bitex::Ask }
  end

  describe '#profit' do
    subject { described_class.profit }

    before(:each) { described_class.store = store }

    let(:profit) { Faker::Number.normal(40, 10).truncate(2).to_d }

    context 'without store' do
      let(:store) { nil }
      let(:error) { "undefined method `selling_profit' for nil:NilClass" }

      it { expect { subject}.to raise_exception(NoMethodError, error) }
    end

    context 'with created store' do
      let(:store) { create(:store, selling_profit: profit) }

      it 'and loaded selling_profit, prioritize Store value' do
        should eq profit
      end

      context 'with nil selling_profit, prioritize Settings value' do
        before(:each) do
          store.update(selling_profit: nil)
          BitexBot::SettingsClass.any_instance.stub(selling: build(:selling_settings, profit: profit))
        end

        it { should eq profit }
      end
    end
  end

  describe '#remote value to use' do
    subject { described_class.remote_value_to_use(value, price) }

    before(:each) { described_class.stub(fx_rate: fx_rate) }

    let(:value) { Faker::Number.normal(40, 10).truncate(2).to_d }
    let(:price) { Faker::Number.normal(40, 10).truncate(2).to_d }
    let(:fx_rate) { Faker::Number.normal(10, 8).truncate(2).to_d }

    it { should eq value * price }
  end

  describe '#safest price' do
    subject { BitexBot::OrderBookSimulator }

    before(:each) { subject.stub(fx_rate: fx_rate) }

    let(:taker_orders) { bitstamp_api_wrapper_order_book.asks }
    let(:taker_transactions) { bitstamp_api_wrapper_transactions_stub }
    let(:crypto_to_use) { Faker::Number.normal(15, 1).truncate(2).to_d }
    let(:fx_rate) { Faker::Number.normal(10, 8).truncate(2).to_d }

    it do
      should receive(:run).with(BitexBot::Settings.time_to_live, taker_transactions, taker_orders, nil, crypto_to_use)
      described_class.safest_price(taker_transactions, taker_orders, crypto_to_use)
    end
  end

  describe '#value to use' do
    subject { described_class.value_to_use }

    before(:each) { described_class.store = store }

    let(:profit) { Faker::Number.normal(40, 10).truncate(2).to_d }

    context 'without store' do
      let(:store) { nil }
      let(:error) { "undefined method `selling_quantity_to_sell_per_order' for nil:NilClass" }

      it { expect { subject }.to raise_exception(NoMethodError, error) }
    end

    context 'with created store' do
      context 'with loaded selling_quantity_to_sell_per_order, prioritize Store value' do
        let(:store) { create(:store, selling_quantity_to_sell_per_order: profit) }

        it { should eq profit }
      end

      context 'with nil selling_quantity_to_sell_per_order, prioritize Settings value' do
        before(:each) { BitexBot::SettingsClass.any_instance.stub(selling: build(:selling_settings, quantity_to_sell_per_order: profit)) }

        let(:store) { create(:store, selling_quantity_to_sell_per_order: nil) }

        it { should eq profit }
      end
    end
  end

  describe '#fx rate' do
    subject { described_class.fx_rate }

    before(:each) { BitexBot::SettingsClass.any_instance.stub(selling: build(:selling_settings, fx_rate: fx_rate)) }

    let(:fx_rate) { Faker::Number.normal(40, 10).truncate(2).to_d }

    it { should eq fx_rate }
  end
end
