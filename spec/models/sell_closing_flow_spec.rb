require 'spec_helper'

describe BitexBot::SellClosingFlow do
  describe 'closes' do
    before(:each) { stub_bitstamp_trade(:buy) }

    let(:flow) { subject.class.last }
    let(:close) { flow.close_positions.first }
    let(:order_id) { '1' }

    it 'a single open position completely' do
      open = create(:open_sell)
      subject.class.close_open_positions

      open.reload.closing_flow.should eq flow

      flow.open_positions.should eq [open]
      flow.desired_price.should eq 290
      flow.quantity.should eq 2
      flow.amount.should eq 600
      flow.btc_profit.should be_nil
      flow.fiat_profit.should be_nil

      close.order_id.should eq order_id
      close.amount.should be_nil
      close.quantity.should be_nil
    end

    it 'an aggregate of several open positions' do
      open_one = create(:tiny_open_sell)
      open_two = create(:open_sell)
      subject.class.close_open_positions

      open_one.reload.closing_flow.should eq flow
      open_two.reload.closing_flow.should eq flow

      flow.open_positions.should eq [open_one, open_two]
      flow.desired_price.should eq '290.4_975_124_378_109'.to_d
      flow.quantity.should eq 2.01
      flow.amount.should eq 604
      flow.btc_profit.should be_nil
      flow.fiat_profit.should be_nil

      close.order_id.should eq order_id
      close.amount.should be_nil
      close.quantity.should be_nil
    end
  end

  describe 'when there are errors placing the closing order' do
    before(:each) { BitstampApiWrapper.stub(send_order: nil) }

    let(:flow) { subject.class.last }

    it 'keeps trying to place a closed position on bitstamp errors' do
      BitstampApiWrapper.stub(find_lost: nil)
      open = create(:open_sell)
      expect do
        subject.class.close_open_positions
      end.to raise_exception(OrderNotFound)

      open.reload.closing_flow.should eq flow

      flow.open_positions.should eq [open]
      flow.desired_price.should eq 290
      flow.quantity.should eq 2
      flow.btc_profit.should be_nil
      flow.fiat_profit.should be_nil
      flow.close_positions.should be_empty
    end

    let(:amount) { 1_000.to_d }
    let(:price) { 2_000.to_d }
    let(:id) { 1_234 }
    let(:type) { 1 }

    it 'retries until it finds the lost order in the bitstamp' do
      counter = 0
      BitstampApiWrapper.stub(:find_lost) do
        counter += 1
        next if counter < 3
        double(amount: amount, price: price, type: type, id: id, datetime: DateTime.now.to_s)
      end
      open = create(:open_sell)
      subject.class.close_open_positions

      counter.should eq 3

      flow.close_positions.should_not be_empty
      flow.close_positions.first do |position|
        position.id.should be id
        position.type.should be type
        position.amount.should be amount0
        position.price.should be price
      end
    end
  end

  it 'does not try to close if the amount is too low' do
    create(:tiny_open_sell)
    expect do
      subject.class.close_open_positions.should be_nil
    end.not_to change{ subject.class.count }
  end

  it 'does not try to close if there are no open positions' do
    expect do
      subject.class.close_open_positions.should be_nil
    end.not_to change{ subject.class.count }
  end

  describe 'when syncinc executed orders' do
    before(:each) do
      stub_bitstamp_trade(:buy)
      stub_bitstamp_empty_user_transactions
      create(:tiny_open_sell)
      create(:open_sell)
    end

    let(:flow) { subject.class.last }
    let(:close) { flow.close_positions.last  }

    it 'syncs the executed orders, calculates profit' do
      subject.class.close_open_positions
      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)

      close.amount.should eq '583.905'.to_d
      close.quantity.should eq 2.01

      flow.should be_done
      flow.btc_profit.should be_zero
      flow.fiat_profit.should eq '20.095'.to_d
    end

    context 'with other fx rate and closed open positions' do
      let(:fx_rate) { 10.to_d }
      let(:positions_balance_amount) { flow.open_positions.sum(:amount) - flow.positions_balance_amount }

      before(:each) do
        BitexBot::Settings.stub(fx_rate: fx_rate)
        subject.class.close_open_positions

        stub_bitstamp_orders_into_transactions
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end

      it 'syncs the executed orders, calculates profit with other fx rate' do
        flow.should be_done
        flow.btc_profit.should be_zero
        flow.fiat_profit.should eq positions_balance_amount
      end
    end

    it 'retries closing at a higher price every minute' do
      subject.class.close_open_positions

      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change{ BitexBot::CloseSell.count }
      flow.should_not be_done

      # Immediately calling sync again does not try to cancel the ask.
      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      Bitstamp.orders.all.size.should eq 1

      # Partially executes order, and 61 seconds after that sync_closed_positions tries to cancel it.
      stub_bitstamp_orders_into_transactions(ratio: 0.5)
      Timecop.travel(61.seconds.from_now)

      Bitstamp.orders.all.size.should eq 1
      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change{ BitexBot::CloseSell.count }

      Bitstamp.orders.all.size.should be_zero
      flow.should_not be_done

      # Next time we try to sync_closed_positions the flow detects the previous close_buy was cancelled correctly so it syncs
      # it's total amounts and tries to place a new one.
      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.to change{ BitexBot::CloseSell.count }.by(1)

      flow.close_positions.first.tap do |close|
        close.amount.should eq '291.9525'.to_d
        close.quantity.should eq 1.005
      end

      # The second ask is executed completely so we can wrap it up and consider this closing flow done.
      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      flow.close_positions.last.tap do |close|
        close.amount.should eq '291.953597'.to_d
        close.quantity.should eq '1.0049'.to_d
      end
      flow.should be_done
      flow.btc_profit.should eq '-0.0001'.to_d
      flow.fiat_profit.should eq '20.093903'.to_d
    end

    it 'does not retry for an amount less than minimum_for_closing' do
      subject.class.close_open_positions

      20.times do
        Timecop.travel(60.seconds.from_now)
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end

      stub_bitstamp_orders_into_transactions(ratio: 0.999)
      Bitstamp.orders.all.first.cancel!

      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change{ BitexBot::CloseSell.count }

      flow.should be_done
      flow.btc_profit.should eq '-0.0224895'.to_d
      flow.fiat_profit.should eq '20.66566825'.to_d
    end

    it 'can lose BTC if price had to be raised dramatically' do
      # This flow is forced to spend the original USD amount paying more than expected, thus regaining less BTC than what was
      # sold on bitex.
      subject.class.close_open_positions

      60.times do
        Timecop.travel(60.seconds.from_now)
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end

      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      flow.reload.should be_done
      flow.btc_profit.should eq '-0.1709'.to_d
      flow.fiat_profit.should eq '20.08575'.to_d

      close = flow.close_positions.last
      (close.amount / close.quantity).should eq '317.5'.to_d
    end
  end
end
