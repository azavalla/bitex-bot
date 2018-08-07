require 'spec_helper'

describe BitexBot::BuyClosingFlow do
  it { should have_many(:open_positions).class_name('OpenBuy').with_foreign_key(:closing_flow_id) }
  it { should have_many(:close_positions).class_name('CloseBuy').with_foreign_key(:closing_flow_id) }

  it_behaves_like BitexBot::ClosingFlow

  describe '#open position class' do
    it { described_class.open_position_class.should eq BitexBot::OpenBuy }
  end

  describe '#fx rate' do
    before(:each) { BitexBot::SettingsClass.any_instance.stub(buying_fx_rate: fx_rate) }

    let(:fx_rate) { Faker::Number.normal(10, 1).truncate.to_d }

    it { described_class.fx_rate.should eq fx_rate }
  end

  describe '#estimate fiat profit' do
    before(:each) do
      described_class.any_instance.stub(positions_balance_amount: balance)
      create_list(:open_buy, 5, closing_flow: subject)
    end

    let(:open_positions_amounts) { subject.open_positions.sum(:amount) }
    let(:balance) { Faker::Number.normal(10, 1).truncate.to_d }

    it { subject.send(:estimate_fiat_profit).should eq balance - open_positions_amounts }
  end

  describe '#estimate crypto profit' do
    subject { flow.send(:estimate_crypto_profit) }

    before(:each) { create_list(:close_buy, 5, closing_flow_id: flow.id) }

    let(:flow) { create(:buy_closing_flow, quantity: quantity) }
    let(:quantity) { Faker::Number.normal(10, 1).truncate.to_d }

    it { should eq quantity - flow.close_positions.sum(:quantity) }
  end

  describe '#next price and quantity' do
    subject { flow.send(:next_price_and_quantity) }

    before(:each) do
      flow.stub(price_variation: price_variation)
      create_list(:close_buy, 5, closing_flow_id: flow.id)
    end

    let(:flow) { create(:buy_closing_flow, quantity: quantity, desired_price: desired_price) }
    let(:quantity) { Faker::Number.normal(10, 1).truncate.to_d }
    let(:desired_price) { Faker::Number.normal(100, 1).truncate.to_d }

    let(:price_variation) { (flow.close_positions.count**2 * 0.03).to_d }

    let(:next_price) { desired_price - price_variation }
    let(:next_quantity) { quantity - flow.close_positions.sum(:quantity) }

    it { should eq [next_price, next_quantity] }
  end

  describe '#order method' do
    it { subject.send(:order_method).should eq :sell }
  end

  describe '#close open positions' do
    subject { described_class.close_open_positions }

    it 'with empty open positions' do
      should be_nil
      described_class.should_not be_any
    end

    context 'with some open positions' do
      before(:each) do
        BitexBot::Robot.stub(taker: BitexBot::Api::Bitstamp.new(build(:bitstamp_taker_settings)))
        create_list(:seq_open_buy, 5)
      end

      let(:open_positions) { BitexBot::OpenBuy.last(5) }

      context 'then open positions in the taker market' do
        before(:each) { BitexBot::Robot.taker.stub(enough_order_size?: enough) }

        context 'have not enough size' do
          let(:enough) { false }

          it 'fails' do
            should be_nil
            described_class.should_not be_any
          end
        end

        context 'have enough size' do
          before(:each) do
            BitexBot::Robot.taker.stub(place_order: order)
            BitexBot::Settings.stub(buying_fx_rate: fx_rate)
          end

          let(:enough) { true }

          let(:quantity) { open_positions.sum(&:quantity).truncate(2)  }
          let(:amount) { open_positions.sum(&:amount).truncate(2) }
          let(:price) { open_positions.map { |p| p.quantity * p.opening_flow.suggested_closing_price }.sum / quantity }
          let(:fx_rate) { Faker::Number.normal(10, 1).truncate.to_d }

          let(:order) { BitexBot::Api::Order.new(order_id, :sell, price, quantity.round(4), DateTime.now.to_i, nil) }
          let(:order_id) { Faker::Number.number(10).to_i }

          let(:closing_flow) { create(:buy_closing_flow, quantity: quantity, desired_price: price) }

          describe '#create order and close position' do
            subject { closing_flow.send(:create_order_and_close_position, quantity, price) }

            it 'place order on taker market and create a new close position' do
              BitexBot::Robot.taker.should receive(:place_order).with(closing_flow.send(:order_method), price, quantity)
              expect { subject }.to change { BitexBot::CloseBuy.count }.by(1)

              should be_a(BitexBot::CloseBuy)
              should eq closing_flow.close_positions.find_by(order_id: order.id)
            end
          end

          describe '#create closing flow!' do
            subject { described_class.create_closing_flow!(price, quantity, amount, open_positions) }

            it 'success' do
              expect_any_instance_of(described_class).to receive(:create_order_and_close_position).with(quantity, price.round(15))
              expect { subject }.to change { described_class.count }.by(1)
              should be_a(described_class)

              subject.desired_price.should eq price.round(15)
              subject.quantity.should eq quantity
              subject.amount.should eq amount
              subject.fx_rate.should eq fx_rate
              subject.open_positions.should eq open_positions

              subject.done.should be_falsey
              subject.crypto_profit.should be_nil
              subject.fiat_profit.should be_nil
            end
          end

          it 'success' do
            BitexBot::Robot.taker.should receive(:enough_order_size?)
            should be_a(described_class)

            subject.close_positions.find_by_order_id(order_id).tap do |close_position|
              close_position.should be_present
              close_position.should be_a(BitexBot::CloseBuy)
              close_position.amount.should be_nil
              close_position.quantity.should be_nil
            end
          end
        end
      end
    end
  end

  describe '#suggested amount' do
    subject { described_class.suggested_amount(positions) }

    let(:positions) { create_list(:seq_open_buy, 5) }
    let(:amount) { positions.map { |p| p.quantity * p.opening_flow.suggested_closing_price }.sum }

    it { should eq amount }
  end

  describe '#lastet close' do
    before(:each) { create(:close_buy, created_at: date, closing_flow_id: flow.id) }

    subject { flow.send(:latest_close) }

    let(:flow) { create(:buy_closing_flow) }
    let(:date) { Time.now }

    it { should eq flow.close_positions.last }

    describe '#expired?' do
      before(:each) do
        Timecop.freeze
        described_class.stub(close_time_to_live: time_to_live)
      end

      subject { start_time { flow.send(:expired?) } }

      let(:time_to_live) { Faker::Number.between(20, 30) }
      let(:date) { offset.seconds.ago }

      def start_time
        Timecop.return
        yield
      end

      context 'with expired flow' do
        let(:offset) { time_to_live + 10 }

        it { should be_truthy }
      end

      context 'with active flow' do
        let(:offset) { time_to_live - 10 }

        it { should be_falsey }
      end
    end
  end

  describe '#sync closed positions' do
    before(:each) { flow.stub(:latest_close) { latest_close } }

    after(:each) { flow.sync_closed_positions }

    let(:flow) { create(:buy_closing_flow) }

    context 'without latest close' do
      let(:latest_close) { nil }

      it { flow.should receive(:create_initial_order_and_close_position!) }
    end

    context 'with latest close' do
      before(:each) { create(:close_buy, closing_flow_id: flow.id) }

      let(:latest_close) { BitexBot::CloseBuy.where(closing_flow_id: flow.id).last }

      it { flow.should receive(:create_or_cancel!) }
    end
  end

  describe '#create initial order and close positions!' do
    after(:each) { flow.create_initial_order_and_close_position! }

    let(:flow) { create(:buy_closing_flow, quantity: quantity, desired_price: price) }
    let(:quantity) { Faker::Number.normal(100, 10).to_d }
    let(:price) { Faker::Number.normal(100, 10).to_d }

    it { flow.should receive(:create_order_and_close_position).with(quantity, price) }
  end

  describe '#positions balance amount' do
    before(:each) { create(:close_buy, closing_flow_id: flow.id) }

    subject { flow.positions_balance_amount }

    let(:positions) { BitexBot::CloseBuy.last(5) }
    let(:flow) { create(:buy_closing_flow, fx_rate: fx_rate) }
    let(:fx_rate) { Faker::Number.normal(5, 1).round(2).to_d }

    it { should eq (positions.sum(&:amount) * fx_rate) }
  end

  context 'with maker and taker' do
    subject { described_class.last }

    before(:each) do
      BitexBot::Robot.stub(maker: BitexBot::Api::Bitex.new(build(:bitex_maker_settings)))
      BitexBot::Robot.stub(taker: BitexBot::Api::Bitstamp.new(build(:bitstamp_taker_settings)))
    end

    describe 'closes' do
      before(:each) { stub_bitstamp_trade(:sell) }

      let(:close_buy) { subject.close_positions.first }

      it 'a single open position completely' do
        open = create(:open_buy)
        described_class.close_open_positions

        open.reload.closing_flow.should eq subject

        subject.open_positions.should eq [open]

        # esto lo dejo por acá, pero deberia estar en los assertions de la creacion
        # subject.desired_price.should >= open.price # 310
        # subject.quantity.should eq open.quantity
        # subject.amount.should eq open.amount

        # esto se puebla cuando vendió del otro lado, cuando termine dec errar la posicion va a calcular cuanto le ganó/perdió
        # pensar en el descriptor de esto
        subject.crypto_profit.should be_nil
        subject.fiat_profit.should be_nil
        close_buy.amount.should be_nil
        close_buy.quantity.should be_nil
      end

      it 'an aggregate of several open positions' do
        open_one = create(:tiny_open_buy)
        open_two = create(:open_buy)
        described_class.close_open_positions

        open_one.reload.closing_flow.should eq subject
        open_two.reload.closing_flow.should eq subject

        subject.open_positions.should eq [open_one, open_two]

        # esto podria estar tambien en el assertion de la creacion
        #
        # aca el desired price es de la posicion abierta con menor price, sumandole el step
        # subject.desired_price.should eq '310.4_975_124_378_109'.to_d
        #
        # idem quantity
        # subject.quantity.should eq 2.01.to_d
        #
        # el amount es el amount de todas las posiciones abiertas
        # subject.amount.should eq 604

        subject.crypto_profit.should be_nil
        subject.fiat_profit.should be_nil

        close_buy.amount.should be_nil
        close_buy.quantity.should be_nil
      end
    end

    describe 'when there are errors placing the closing order' do
      before(:each) { BitexBot::Robot.taker.stub(send_order: nil) }

      it 'keeps trying to place a closed position on bitstamp errors' do
        BitexBot::Robot.taker.stub(find_lost: nil)
        open = create(:open_buy)

        expect { described_class.close_open_positions }.to raise_exception(BitexBot::Api::OrderNotFound)

        open.reload.closing_flow.should eq subject

        subject.open_positions.should eq [open]

        subject.crypto_profit.should be_nil
        subject.fiat_profit.should be_nil

        subject.close_positions.should be_empty
      end

      context 'retries until it finds the lost order' do
        before(:each) do
          BitexBot::Robot.taker.stub(orders: [BitexBot::Api::Order.new(1, :sell, 310, 2.5, 1.minute.ago.to_i)])
          create(:open_buy)
          described_class.close_open_positions
        end

        it do
          subject.close_positions.should_not be_empty
          subject.close_positions.first do |position|
            position.id.should eq 1234
            position.type.should eq 1
            position.amount.should eq 1000
            position.price.should eq 2000
          end
        end
      end
    end

    context 'does not try to close if the amount is too low' do
      before(:each) { create(:tiny_open_buy) }

      it { expect { described_class.close_open_positions.should be_nil }.not_to change { described_class.count } }
    end

    it 'does not try to close if there are no open positions' do
      expect { described_class.close_open_positions.should be_nil }.not_to change { described_class.count }
    end

    describe 'when sync executed orders' do
      before(:each) do
        stub_bitstamp_trade(:sell)
        stub_bitstamp_empty_user_transactions
        create(:tiny_open_buy)
        create(:open_buy)
      end

      let(:last_close_buy) { subject.close_positions.last }

      context 'syncs the executed orders, calculates profit' do
        before(:each) do
          described_class.close_open_positions
          stub_bitstamp_orders_into_transactions
          subject.sync_closed_positions
        end

        it do
          last_close_buy.amount.should eq 624.105
          last_close_buy.quantity.should eq 2.01

          should be_done
          subject.crypto_profit.should be_zero
          subject.fiat_profit.should eq 20.105
        end
      end

      context 'with other fx rate and closed open positions' do
        let(:fx_rate) { 10.to_d }
        let(:positions_balance_amount) { subject.positions_balance_amount - subject.open_positions.sum(:amount) }

        before(:each) do
          BitexBot::Settings.stub(fx_rate: fx_rate)
          described_class.close_open_positions

          stub_bitstamp_orders_into_transactions
          subject.sync_closed_positions
        end

        it 'syncs the executed orders, calculates profit with other fx rate' do
          should be_done
          subject.crypto_profit.should be_zero
          subject.fiat_profit.should eq positions_balance_amount
        end
      end

      it 'retries closing at a lower price every minute' do
        described_class.close_open_positions

        expect { subject.sync_closed_positions }.not_to change { BitexBot::CloseBuy.count }
        should_not be_done

        # Immediately calling sync again does not try to cancel the ask.
        subject.sync_closed_positions
        Bitstamp.orders.all.size.should eq 1

        # Partially executes order, and 61 seconds after that sync_closed_positions tries to cancel it.
        stub_bitstamp_orders_into_transactions(ratio: 0.5)
        Timecop.travel(61.seconds.from_now)

        Bitstamp.orders.all.size.should eq 1
        expect { subject.sync_closed_positions }.not_to change { BitexBot::CloseBuy.count }

        Bitstamp.orders.all.size.should be_zero
        should_not be_done

        # Next time we try to sync_closed_positions the flow detects the previous close_buy was cancelled correctly so it syncs
        # it's total amounts and tries to place a new one.
        expect { subject.sync_closed_positions }.to change { BitexBot::CloseBuy.count }.by(1)

        subject.close_positions.first.tap do |close_buy|
          close_buy.amount.should eq 312.052_5
          close_buy.quantity.should eq 1.005
        end

        # The second ask is executed completely so we can wrap it up and consider this closing flow done.
        stub_bitstamp_orders_into_transactions

        subject.sync_closed_positions
        subject.close_positions.last.tap do |close_buy|
          close_buy.amount.should eq 312.02_235
          close_buy.quantity.should eq 1.005
        end
        should be_done
        subject.crypto_profit.should be_zero
        subject.fiat_profit.should eq 20.07_485
      end

      it 'does not retry for an amount less than taker minimun order size' do
        2.times { described_class.close_open_positions }
        subject
        stub_bitstamp_orders_into_transactions(ratio: 0.999)
        Bitstamp.orders.all.first.cancel!

        expect { subject.sync_closed_positions }.not_to change { BitexBot::CloseBuy.count }

        should be_done
        subject.crypto_profit.should eq 0.00_201
        subject.fiat_profit.should eq 19.480_895
      end

      it 'can lose USD if price had to be dropped dramatically' do
        # This flow is forced to sell the original BTC quantity for less, thus regaining
        # less USD than what was spent on bitex.
        described_class.close_open_positions

        60.times do
          Timecop.travel(60.seconds.from_now)
          subject.sync_closed_positions
        end

        stub_bitstamp_orders_into_transactions

        subject.sync_closed_positions
        subject.reload.should be_done
        subject.crypto_profit.should be_zero
        subject.fiat_profit.should eq -34.165

        (last_close_buy.amount / last_close_buy.quantity).should eq 283.5
      end
    end
  end
end
