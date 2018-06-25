require 'spec_helper'

describe BitexBot::Robot do
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
    BitexBot::Settings.stub(
      time_to_live: 10,
      buying: double(amount_to_spend_per_order: 50, profit: 0),
      selling: double(quantity_to_sell_per_order: 1, profit: 0),
      mailer: double(
        from: 'test@test.com',
        to: 'test@test.com',
        delivery_method: :test,
        options: {}
      )
    )

    Bitex::Profile.stub(
      get: {
        fee: 0.5,
        usd_balance: 10_000.0,  # Total USD balance
        usd_reserved: 2_000.0,  # USD reserved in open orders
        usd_available: 8_000.0, # USD available for trading
        btc_balance: 20.0,      # Total BTC balance
        btc_reserved: 5.0,      # BTC reserved in open orders
        btc_available: 15.0,    # BTC available for trading
        ltc_balance: 250.0,     # Total LTC balance
        ltc_reserved: 100.0,    # LTC reserved in open orders
        ltc_available: 150.0    # Total LTC balance
      }
    )

    stub_bitex_active_orders
    stub_bitstamp_trade(:sell)
    stub_bitstamp_trade(:buy)
    stub_bitstamp_api_wrapper_balance
    stub_bitstamp_api_wrapper_order_book
    stub_bitstamp_transactions
    stub_bitstamp_empty_user_transactions
  end

  let(:bot) { described_class.new }

  it 'Starts out by creating opening flows that timeout' do
    stub_bitex_active_orders
    stub_bitstamp_api_wrapper_order_book

    bot.trade!
    stub_bitex_transactions

    buying = BitexBot::BuyOpeningFlow.last
    selling = BitexBot::SellOpeningFlow.last

    Timecop.travel(10.minutes.from_now)
    bot.trade!

    buying.reload.should be_settling
    selling.reload.should be_settling

    bot.trade!
    buying.reload.should be_finalised
    selling.reload.should be_finalised
  end

  it 'creates alternating opening flows' do
    Bitex::Trade.stub(all: [])
    bot.trade!

    BitexBot::BuyOpeningFlow.active.count.should eq 1
    Timecop.travel(2.seconds.from_now)
    bot.trade!

    BitexBot::BuyOpeningFlow.active.count.should eq 1
    Timecop.travel(5.seconds.from_now)
    bot.trade!

    BitexBot::BuyOpeningFlow.active.count.should eq 2

    # When transactions appear, all opening flows should get old and die.
    # We stub our finder to make it so all orders have been successfully cancelled.
    stub_bitex_transactions

    Timecop.travel(5.seconds.from_now)
    2.times { bot.trade! }

    BitexBot::BuyOpeningFlow.active.count.should eq 1
    Timecop.travel(5.seconds.from_now)
    bot.trade!

    BitexBot::BuyOpeningFlow.active.count.should be_zero
  end

  it 'does not place new opening flows until all closing flows are done' do
    bot.trade!
    stub_bitex_transactions

    expect { bot.trade! }.to change { BitexBot::BuyClosingFlow.count }.by(1)

    Timecop.travel(15.seconds.from_now)
    2.times { bot.trade! }

    bot.should be_active_closing_flows
    bot.should_not be_active_opening_flows
    stub_bitstamp_orders_into_transactions

    expect do
      bot.trade!
      bot.should_not be_active_closing_flows
    end.to change { BitexBot::BuyOpeningFlow.count }.by(1)
  end

  context 'with another bot updating store flags' do
    let(:other_bot) { described_class.new }

    def with_transaction
      yield

      expect { bot.trade! }.not_to change { BitexBot::BuyOpeningFlow.count }
    end

    it 'does not place new opening flows when ordered to hold' do
      with_transaction { other_bot.store.update!(hold: true) }
    end

    it 'stops trading when fiat stop is reached' do
      with_transaction { other_bot.store.update!(btc_stop: 30) }
    end

    it 'stops trading when btc stop is reached' do
      with_transaction { other_bot.store.update!(fiat_stop: 11_000) }
    end

    context 'with empty bitex trades' do
      before(:each) { Bitex::Trade.stub(all: []) }

      def with_transaction
        yield

        expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)

        Timecop.travel(1.minute.from_now)
        # Re-stub so order book does not get old
        stub_bitstamp_order_book

        expect { bot.trade! }.not_to change { Mail::TestMailer.deliveries.count }

        Timecop.travel(31.minutes.from_now)
        # Re-stub so order book does not get old
        stub_bitstamp_order_book

        expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)
      end

      it 'warns every 30 minutes when usd warn is reached' do
        with_transaction { other_bot.store.update(fiat_warning: 11_000) }
      end

      it 'warns every 30 minutes when btc warn is reached' do
        with_transaction { other_bot.store.update!(btc_warning: 30) }
      end
    end
  end

  it 'updates taker_fiat and taker_btc' do
    bot.trade!

    bot.store.taker_fiat.should_not be_nil
    bot.store.taker_btc.should_not be_nil
  end

  it 'notifies exceptions and sleeps' do
    described_class.taker.stub(:balance) { raise StandardError.new('oh moova') }

    expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)
  end
end
