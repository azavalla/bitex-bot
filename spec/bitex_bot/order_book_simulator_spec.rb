require 'spec_helper'

describe BitexBot::OrderBookSimulator do
  describe 'when buying on bitex to sell somewhere else' do
    let(:bids) { bitstamp_api_wrapper_order_book.bids }

    def simulate(volatility, amount)
      described_class.run(volatility, bitstamp_api_wrapper_transactions_stub, bids, amount, nil)
    end

    it 'gets the safest price' do
      simulate(0, 20).should eq 30
    end

    it 'adjusts for medium volatility' do
      simulate(3, 20).should eq 25
    end

    it 'adjusts for high volatility' do
      simulate(6, 20).should eq 20
    end

    it 'big orders dig deep' do
      simulate(0, 180).should eq 15
    end

    it 'big orders with high volatility' do
      simulate(6, 100).should eq 10
    end

    it 'still returns a price on very high volatility and low liquidity' do
      simulate(10_000, 10_000).should eq 10
    end
  end

  describe 'when selling on bitex to buy somewhere else' do
    let(:asks) { bitstamp_api_wrapper_order_book.asks }

    def simulate(volatility, quantity)
      described_class.run(volatility, bitstamp_api_wrapper_transactions_stub, asks, nil, quantity)
    end

    it 'gets the safest price' do
      simulate(0, 2).should eq 10
    end

    it 'adjusts for medium volatility' do
      simulate(3, 2).should eq 15
    end

    it 'adjusts for high volatility' do
      simulate(6, 2).should eq 25
    end

    it 'big orders dig deep' do
      simulate(0, 8).should eq 25
    end

    it 'big orders with high volatility dig deep' do
      simulate(6, 6).should eq 30
    end
  end

  describe '#estimate_quantity_to_skip' do
    before(:each) do
      BitexBot::Settings.stub(taker: build(:bitex_taker))
      BitexBot::Robot.setup
      stub_bitex_transactions(oldest_transaction)
    end

    # The stubed transactions have timestamp close to the current.
    let(:oldest_transaction) { build(:bitex_sell, id: oldest_id, created_at: oldest_timestamp) }

    let(:oldest_id) { Faker::Number.number }

    # When antiquity is smallest, more current is the oldest timestamp.
    let(:oldest_timestamp) { Time.at(antiquity.seconds.ago) }
    let(:antiquity) { 1_300_000_000 }

    context 'transactions amount sum' do
      let(:transactions) { BitexBot::Robot.taker.transactions }

      context 'when there isn´t volatility, no date is greater than the date of the most recent' do
        # A lower volatility reduces the scope, limiting it closer to the most current record.
        let(:volatility) { 0 }

        # Then none will be within reach.
        let(:estimate_quantity) { 0 }

        it { described_class.estimate_quantity_to_skip(volatility, transactions).should eq estimate_quantity }
      end

      context 'when volatility leaves out the oldest transaction' do
        # A greater volatility than the antiquity, will leave the oldest record within range.
        let(:volatility) { antiquity - 1 }

        # Sum of the amounts without the oldest.
        let(:estimate_quantity) { transactions.reject { |t| t.id == oldest_id }.sum(&:amount) }

        it { described_class.estimate_quantity_to_skip(volatility, transactions).should eq estimate_quantity }
      end

      context 'leave inside the oldest transaction' do
        # A greater volatility than the antiquity, will leave the oldest record within range.
        let(:volatility) { antiquity + 1 }

        # Sum of the amounts without the oldest.
        let(:estimate_quantity) { transactions.sum(&:amount) }

        it { described_class.estimate_quantity_to_skip(volatility, transactions).should eq estimate_quantity }
      end
    end
  end

  describe '#best_price' do
    let(:price) { Faker::Number.decimal }
    let(:target) { Faker::Number.decimal }
    let(:currency) { Faker::Currency.code }

    it { described_class.best_price(currency, target, price).should eq price }
  end

  describe '#best_price?, when the volume' do
    let(:volume) { 20 }
    let(:target) { 30 }

    context 'is greater than the subtraction between the objective and seen' do
      let(:seen) { 20 }

      it { volume.should > target - seen }
      it { described_class.best_price?(volume, target, seen).should be_truthy }

      context 'or equals' do
        let(:seen) { 10 }

        it { volume.should eq target - seen }
        it { described_class.best_price?(volume, target, seen).should be_truthy }
      end
    end

    context 'is lower than the subtraction between the objective and seen' do
      let(:seen) { 5 }

      it { volume.should < target - seen }
      it { described_class.best_price?(volume, target, seen).should be_falsey }
    end
  end
end
