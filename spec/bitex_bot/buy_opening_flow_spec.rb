require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  it_behaves_like BitexBot::OpeningFlow

  describe '#create for market' do
    before(:each) { BitexBot::Robot.setup }

    let(:taker_orders) { bitstamp_api_wrapper_order_book.bids }
    let(:taker_transactions) { bitstamp_api_wrapper_transactions_stub }
    let(:maker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:taker_fee) { Faker::Number.normal(1, 0.5).truncate(2).to_d }
    let(:store) { create(:store) }

    subject { described_class.create_for_market(taker_balance, taker_orders, taker_transactions, maker_fee, taker_fee, store) }

    context 'the external value remote calculated gives 2 approximately' do
      context 'when taker balance is lower or equal than remote value, that later it will be used to calculate bitex price' do
        before(:each) { described_class.order_class.stub(create!: order) }

        let(:order) { build(:bitex_bid) }
        let(:taker_balance) { Faker::Number.normal(1_000, 10).truncate(2).to_d }

        it_behaves_like 'fails, when creating any validation'
        it_behaves_like 'fails, when try place order on maker, but you do not have sufficient funds'

        it 'success' do
          subject.order_id.should eq order.id
          subject.should be_a(described_class)
          subject.price.should <= subject.suggested_closing_price * described_class.fx_rate
        end
      end

      context 'fails, when there are not enough BTC to sell in the other exchange' do
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

  describe '#maker price' do
    before(:each) do
      described_class.store = create(:store)

      # it's indifferent here, but not on sell opening flow.
      described_class.stub(value_to_use: value_to_use)
      described_class.stub(fx_rate: fx_rate)
      described_class.stub(profit: profit)
    end

    let(:value_to_use) { Faker::Number.normal(50, 10).truncate(2) }
    let(:fx_rate) { Faker::Number.normal(50, 10).truncate(2) }
    let(:profit) { Faker::Number.normal(50, 10).truncate(2) }

    let(:crypto_to_resell) { Faker::Number.normal(50, 10).truncate(2) }

    let(:source_amount) { crypto_to_resell }
    let(:percentile_profit) { 1 - profit / 100 }

    it { described_class.maker_price(crypto_to_resell).should eq value_to_use / crypto_to_resell * percentile_profit }
  end

  describe '#order class' do
    it { described_class.order_class.should eq Bitex::Bid }
  end

  describe '#profit' do
    before(:each) { described_class.store = store }

    let(:profit) { Faker::Number.normal(40, 10).truncate(2).to_d }

    context 'without store' do
      let(:store) { nil }
      let(:error) { "undefined method `buying_profit' for nil:NilClass" }

      it { expect { described_class.profit }.to raise_exception(NoMethodError, error) }
    end

    context 'with created store' do
      let(:store) { create(:store, buying_profit: profit) }

      it 'and loaded buying_profit, prioritize Store value' do
        described_class.profit.should eq profit
      end

      context 'with nil buying_profit, prioritize Settings value' do
        before(:each) do
          store.update(buying_profit: nil)
          BitexBot::SettingsClass.any_instance.stub(buying: build(:buying_settings, profit: profit))
        end

        it { described_class.profit.should eq profit }
      end
    end
  end

  describe '#remote value to use' do
    before(:each) { described_class.stub(fx_rate: fx_rate) }

    let(:value) { Faker::Number.normal(40, 10).truncate(2).to_d }
    let(:price) { Faker::Number.normal(40, 10).truncate(2).to_d }
    let(:fx_rate) { Faker::Number.normal(10, 8).truncate(2).to_d }

    it { described_class.remote_value_to_use(value, price).should eq (value / fx_rate) / price }
  end

  describe '#safest price' do
    before(:each) { described_class.stub(fx_rate: fx_rate) }

    after(:each) { described_class.safest_price(taker_transactions, taker_orders, fiat_to_use) }

    let(:taker_orders) { bitstamp_api_wrapper_order_book.asks }
    let(:taker_transactions) { bitstamp_api_wrapper_transactions_stub }
    let(:fiat_to_use) { Faker::Number.normal(15, 1).truncate(2).to_d }
    let(:fx_rate) { Faker::Number.normal(10, 8).truncate(2).to_d }

    it do
      BitexBot::OrderBookSimulator
        .should receive(:run)
        .with(BitexBot::Settings.time_to_live, taker_transactions, taker_orders, fiat_to_use / fx_rate, nil)
    end
  end

  describe '#value to use' do
    before(:each) { described_class.store = store }

    let(:profit) { Faker::Number.normal(40, 10).truncate(2).to_d }

    context 'without store' do
      let(:store) { nil }
      let(:error) { "undefined method `buying_amount_to_spend_per_order' for nil:NilClass" }

      it { expect { described_class.value_to_use }.to raise_exception(NoMethodError, error) }
    end

    context 'with created store' do
      context 'with loaded buying_amount_to_spend_per_order, prioritize Store value' do
        let(:store) { create(:store, buying_amount_to_spend_per_order: profit) }

        it { described_class.value_to_use.should eq profit }
      end

      context 'with nil buying_amount_to_spend_per_order, prioritize Settings value' do
        before(:each) { BitexBot::SettingsClass.any_instance.stub(buying: build(:buying_settings, amount_to_spend_per_order: profit)) }

        let(:store) { create(:store, buying_amount_to_spend_per_order: nil) }

        it { described_class.value_to_use.should eq profit }
      end
    end
  end

  describe '#fx rate' do
    before(:each) { BitexBot::SettingsClass.any_instance.stub(buying: build(:buying_settings, fx_rate: fx_rate)) }

    let(:fx_rate) { Faker::Number.normal(40, 10).truncate(2).to_d }

    it { described_class.fx_rate.should eq fx_rate }
  end
end
