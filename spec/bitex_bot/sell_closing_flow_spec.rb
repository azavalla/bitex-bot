require 'spec_helper'

describe BitexBot::SellClosingFlow do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitstamp: {
        api_key: 'YOUR_API_KEY', secret: 'YOUR_API_SECRET', client_id: 'YOUR_BITSTAMP_USERNAME'
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  describe 'closes' do
    before(:each) { stub_bitstamp_trade(:buy) }

    let(:flow) { described_class.last }
    let(:close) { flow.close_positions.first }
    let(:order_id) { '1' }

    it 'a single open position completely' do
      open = create(:open_sell)
      described_class.close_open_positions

      open.reload.closing_flow.should eq flow

      flow.open_positions.should eq [open]
      flow.desired_price.should eq 290
      flow.quantity.should eq 2
      flow.amount.should eq 600
      flow.crypto_profit.should be_nil
      flow.fiat_profit.should be_nil

      close.order_id.should eq order_id
      close.amount.should be_nil
      close.quantity.should be_nil
    end

    it 'an aggregate of several open positions' do
      open_one = create(:tiny_open_sell)
      open_two = create(:open_sell)
      described_class.close_open_positions

      open_one.reload.closing_flow.should eq flow
      open_two.reload.closing_flow.should eq flow

      flow.open_positions.should eq [open_one, open_two]
      flow.desired_price.should eq '290.4_975_124_378_109'.to_d
      flow.quantity.should eq 2.01
      flow.amount.should eq 604
      flow.crypto_profit.should be_nil
      flow.fiat_profit.should be_nil

      close.order_id.should eq order_id
      close.amount.should be_nil
      close.quantity.should be_nil
    end
  end

  describe 'when there are errors placing the closing order' do
    before(:each) do
      BitexBot::Robot.taker.stub(send_order: nil)
    end

    let(:flow) { described_class.last }

    it 'keeps trying to place a closed position on bitstamp errors' do
      BitexBot::Robot.taker.stub(find_lost: nil)
      open = create(:open_sell)

      expect { described_class.close_open_positions }.to raise_exception(BitexBot::Api::OrderNotFound)

      open.reload.closing_flow.should eq flow

      flow.open_positions.should eq [open]
      flow.desired_price.should eq 290
      flow.quantity.should eq 2
      flow.crypto_profit.should be_nil
      flow.fiat_profit.should be_nil
      flow.close_positions.should be_empty
    end

    it 'retries until it finds the lost order' do
      BitexBot::Robot.taker.stub(send_order: nil)
      BitexBot::Robot.taker.stub(:orders) do
        [BitexBot::Api::Order.new(1, :buy, 290, 2, 1.minute.ago.to_i)]
      end

      create(:open_sell)
      described_class.close_open_positions

      flow.close_positions.should_not be_empty
      flow.close_positions.first do |position|
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

  describe 'when syncinc executed orders' do
    before(:each) do
      stub_bitstamp_trade(:buy)
      stub_bitstamp_empty_user_transactions
      create(:tiny_open_sell)
      create(:open_sell)
    end

    let(:flow) { described_class.last }
    let(:close) { flow.close_positions.last  }

    it 'syncs the executed orders, calculates profit' do
      described_class.close_open_positions
      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions

      close.amount.should eq 583.905
      close.quantity.should eq 2.01

      flow.should be_done
      flow.crypto_profit.should be_zero
      flow.fiat_profit.should eq 20.095
    end

    context 'with other fx rate and closed open positions' do
      let(:fx_rate) { 10.to_d }
      let(:positions_balance_amount) { flow.open_positions.sum(:amount) - flow.positions_balance_amount }

      before(:each) do
        BitexBot::Settings.stub(fx_rate: fx_rate)
        described_class.close_open_positions

        stub_bitstamp_orders_into_transactions
        flow.sync_closed_positions
      end

      it 'syncs the executed orders, calculates profit with other fx rate' do
        flow.should be_done
        flow.crypto_profit.should be_zero
        flow.fiat_profit.should eq positions_balance_amount
      end
    end

    it 'retries closing at a higher price every minute' do
      described_class.close_open_positions

      expect do
        flow.sync_closed_positions
      end.not_to change{ BitexBot::CloseSell.count }
      flow.should_not be_done

      # Immediately calling sync again does not try to cancel the ask.
      flow.sync_closed_positions
      Bitstamp.orders.all.size.should eq 1

      # Partially executes order, and 61 seconds after that sync_closed_positions tries to cancel it.
      stub_bitstamp_orders_into_transactions(ratio: 0.5)
      Timecop.travel(61.seconds.from_now)

      Bitstamp.orders.all.size.should eq 1
      expect do
        flow.sync_closed_positions
      end.not_to change{ BitexBot::CloseSell.count }

      Bitstamp.orders.all.size.should be_zero
      flow.should_not be_done

      # Next time we try to sync_closed_positions the flow detects the previous close_buy was cancelled correctly so it syncs
      # it's total amounts and tries to place a new one.
      expect do
        flow.sync_closed_positions
      end.to change{ BitexBot::CloseSell.count }.by(1)

      flow.close_positions.first.tap do |close|
        close.amount.should eq '291.9525'.to_d
        close.quantity.should eq 1.005
      end

      # The second ask is executed completely so we can wrap it up and consider this closing flow done.
      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions
      flow.close_positions.last.tap do |close|
        close.amount.should eq 291.953_597
        close.quantity.should eq 1.0_049
      end
      flow.should be_done
      flow.crypto_profit.should eq -0.0_001
      flow.fiat_profit.should eq 20.093_903
    end

    it 'does not retry for an amount less than minimum_for_closing' do
      described_class.close_open_positions

      20.times do
        Timecop.travel(60.seconds.from_now)
        flow.sync_closed_positions
      end

      stub_bitstamp_orders_into_transactions(ratio: 0.999)
      Bitstamp.orders.all.first.cancel!

      expect do
        flow.sync_closed_positions
      end.not_to change{ BitexBot::CloseSell.count }

      flow.should be_done
      flow.crypto_profit.should eq -0.0_224_895
      flow.fiat_profit.should eq 20.66_566_825
    end

    it 'can lose BTC if price had to be raised dramatically' do
      # This flow is forced to spend the original USD amount paying more than expected, thus regaining less BTC than what was
      # sold on bitex.
      described_class.close_open_positions

      60.times do
        Timecop.travel(60.seconds.from_now)
        flow.sync_closed_positions
      end

      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions
      flow.reload.should be_done
      flow.crypto_profit.should eq -0.1_709
      flow.fiat_profit.should eq 20.08_575

      close = flow.close_positions.last
      (close.amount / close.quantity).should eq 317.5
    end
  end
end
