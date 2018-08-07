require 'spec_helper'

describe BitexBot::SellClosingFlow do
  it { should have_many(:open_positions).class_name('OpenSell').with_foreign_key(:closing_flow_id) }
  it { should have_many(:close_positions).class_name('CloseSell').with_foreign_key(:closing_flow_id) }

  it_behaves_like BitexBot::ClosingFlow

  describe '#open position class' do
    it { described_class.open_position_class.should eq BitexBot::OpenSell }
  end

  describe '#fx rate' do
    before(:each) { BitexBot::SettingsClass.any_instance.stub(selling_fx_rate: fx_rate) }

    let(:fx_rate) { Faker::Number.normal(10, 1).truncate.to_d }

    it { described_class.fx_rate.should eq fx_rate }
  end

  describe '#estimate fiat profit' do
    before(:each) do
      described_class.any_instance.stub(positions_balance_amount: balance)
      create_list(:open_sell, 5, closing_flow: subject)
    end

    let(:open_positions_amounts) { subject.open_positions.sum(:amount) }
    let(:balance) { Faker::Number.normal(10, 1).truncate.to_d }

    it { subject.send(:estimate_fiat_profit).should eq open_positions_amounts - balance }
  end

  describe '#estimate crypto profit' do
    subject { flow.send(:estimate_crypto_profit) }

    before(:each) { create_list(:close_sell, 5, closing_flow_id: flow.id) }

    let(:flow) { create(:sell_closing_flow, quantity: quantity) }
    let(:quantity) { Faker::Number.normal(10, 1).truncate.to_d }

    it { should eq flow.close_positions.sum(:quantity) - quantity }
  end

  describe '#next price and quantity' do
    subject { flow.send(:next_price_and_quantity) }

    before(:each) do
      flow.stub(price_variation: price_variation)
      create_list(:close_sell, 5, closing_flow_id: flow.id)
    end

    let(:flow) { create(:sell_closing_flow, quantity: quantity, desired_price: desired_price) }
    let(:quantity) { Faker::Number.normal(10, 1).truncate(2).to_d }
    let(:desired_price) { Faker::Number.normal(100, 1).truncate(2).to_d }

    let(:price_variation) { (flow.close_positions.count**2 * 0.03).to_d }

    let(:next_price) { desired_price + price_variation }
    let(:next_quantity) { ((quantity * desired_price) - flow.close_positions.sum(:amount)) / next_price }

    it { subject.should eq [next_price, next_quantity] }
  end

  describe '#order method' do
    it { subject.send(:order_method).should eq :buy }
  end

  context 'with maker and taker' do
    subject { described_class.last }

    before(:each) do
      BitexBot::Robot.stub(maker: BitexBot::Api::Bitex.new(build(:bitex_maker_settings)))
      BitexBot::Robot.stub(taker: BitexBot::Api::Bitstamp.new(build(:bitstamp_taker_settings)))
    end

    describe 'last close sells' do
      before(:each) { stub_bitstamp_trade(:buy) }

      let(:last_close_sell) { subject.close_positions.first }

      it 'a single open position completely' do
        open = create(:open_sell)
        described_class.close_open_positions

        open.reload.closing_flow.should eq subject

        subject.open_positions.should eq [open]
        subject.desired_price.should eq 290
        subject.quantity.should eq 2
        subject.amount.should eq 600
        subject.crypto_profit.should be_nil
        subject.fiat_profit.should be_nil

        last_close_sell.amount.should be_nil
        last_close_sell.quantity.should be_nil
      end

      it 'an aggregate of several open positions' do
        open_one = create(:tiny_open_sell)
        open_two = create(:open_sell)
        described_class.close_open_positions

        open_one.reload.closing_flow.should eq subject
        open_two.reload.closing_flow.should eq subject

        subject.open_positions.should eq [open_one, open_two]
        subject.desired_price.should eq '290.4_975_124_378_109'.to_d
        subject.quantity.should eq 2.01
        subject.amount.should eq 604
        subject.crypto_profit.should be_nil
        subject.fiat_profit.should be_nil

        last_close_sell.amount.should be_nil
        last_close_sell.quantity.should be_nil
      end
    end

    describe 'when there are errors placing the closing order' do
      before(:each) { BitexBot::Robot.taker.stub(send_order: nil) }

      it 'keeps trying to place a closed position on bitstamp errors' do
        BitexBot::Robot.taker.stub(find_lost: nil)
        open = create(:open_sell)

        expect { described_class.close_open_positions }.to raise_exception(BitexBot::Api::OrderNotFound)

        open.reload.closing_flow.should eq subject

        subject.open_positions.should eq [open]
        subject.desired_price.should eq 290
        subject.quantity.should eq 2
        subject.crypto_profit.should be_nil
        subject.fiat_profit.should be_nil
        subject.close_positions.should be_empty
      end

      it 'retries until it finds the lost order' do
        BitexBot::Robot.taker.stub(orders: [BitexBot::Api::Order.new(1, :buy, 290, 2, 1.minute.ago.to_i)])

        create(:open_sell)
        described_class.close_open_positions

        subject.close_positions.should_not be_empty
        subject.close_positions.first do |position|
          position.id.should eq 1_234
          position.type.should eq 1
          position.amount.should eq 1_000
          position.price.should eq 2_000
        end
      end
    end

    it 'does not try to close if the amount is too low' do
      create(:tiny_open_sell)

      expect { described_class.close_open_positions.should be_nil }.not_to change{ described_class.count }
    end

    it 'does not try to close if there are no open positions' do
      expect { described_class.close_open_positions.should be_nil }.not_to change{ described_class.count }
    end

    describe 'when sync executed orders' do
      before(:each) do
        stub_bitstamp_trade(:buy)
        stub_bitstamp_empty_user_transactions
        create(:tiny_open_sell)
        create(:open_sell)
      end

      let(:last_close_sell) { subject.close_positions.last  }

      it 'syncs the executed orders, calculates profit' do
        described_class.close_open_positions
        stub_bitstamp_orders_into_transactions

        subject.sync_closed_positions

        last_close_sell.amount.should eq 583.905
        last_close_sell.quantity.should eq 2.01

        subject.should be_done
        subject.crypto_profit.should be_zero
        subject.fiat_profit.should eq 20.095
      end

      context 'with other fx rate and closed open positions' do
        let(:fx_rate) { 10.to_d }
        let(:positions_balance_amount) { subject.open_positions.sum(:amount) - subject.positions_balance_amount }

        before(:each) do
          BitexBot::Settings.stub(fx_rate: fx_rate)
          described_class.close_open_positions

          stub_bitstamp_orders_into_transactions
          subject.sync_closed_positions
        end

        it 'syncs the executed orders, calculates profit with other fx rate' do
          subject.should be_done
          subject.crypto_profit.should be_zero
          subject.fiat_profit.should eq positions_balance_amount
        end
      end

      it 'retries closing at a higher price every minute' do
        described_class.close_open_positions

        expect { subject.sync_closed_positions }.not_to change{ BitexBot::CloseSell.count }
        subject.should_not be_done

        # Immediately calling sync again does not try to cancel the ask.
        subject.sync_closed_positions
        Bitstamp.orders.all.size.should eq 1

        # Partially executes order, and 61 seconds after that sync_closed_positions tries to cancel it.
        stub_bitstamp_orders_into_transactions(ratio: 0.5)
        Timecop.travel(61.seconds.from_now)

        Bitstamp.orders.all.size.should eq 1
        expect { subject.sync_closed_positions }.not_to change{ BitexBot::CloseSell.count }

        Bitstamp.orders.all.size.should be_zero
        subject.should_not be_done

        # Next time we try to sync_closed_positions the flow detects the previous close_sell was cancelled correctly so it syncs
        # it's total amounts and tries to place a new one.
        expect { subject.sync_closed_positions }.to change{ BitexBot::CloseSell.count }.by(1)

        subject.close_positions.first.tap do |close_sell|
          close_sell.amount.should eq 291.952_5.to_d
          close_sell.quantity.should eq 1.005
        end

        # The second ask is executed completely so we can wrap it up and consider this closing flow done.
        stub_bitstamp_orders_into_transactions

        subject.sync_closed_positions
        subject.close_positions.last.tap do |close_sell|
          close_sell.amount.should eq 291.953_597
          close_sell.quantity.should eq 1.0_049
        end
        subject.should be_done
        subject.crypto_profit.should eq -0.0_001
        subject.fiat_profit.should eq 20.093_903
      end

      it 'does not retry for an amount less than minimum_for_closing' do
        described_class.close_open_positions

        20.times do
          Timecop.travel(60.seconds.from_now)
          subject.sync_closed_positions
        end

        stub_bitstamp_orders_into_transactions(ratio: 0.999)
        Bitstamp.orders.all.first.cancel!

        expect { subject.sync_closed_positions }.not_to change{ BitexBot::CloseSell.count }

        subject.should be_done
        subject.crypto_profit.should eq -0.0_224_895
        subject.fiat_profit.should eq 20.66_566_825
      end

      it 'can lose BTC if price had to be raised dramatically' do
        # This flow is forced to spend the original USD amount paying more than expected, thus regaining
        # less BTC than what was sold on bitex.
        described_class.close_open_positions

        60.times do
          Timecop.travel(60.seconds.from_now)
          subject.sync_closed_positions
        end

        stub_bitstamp_orders_into_transactions

        subject.sync_closed_positions
        subject.reload.should be_done
        subject.crypto_profit.should eq -0.1_709
        subject.fiat_profit.should eq 20.08_575

        (last_close_sell.amount / last_close_sell.quantity).should eq 317.5
      end
    end
  end
end
