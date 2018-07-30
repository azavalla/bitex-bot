shared_examples_for BitexBot::OpeningFlow do
  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(described_class.statuses)) }

  let(:flow_factory) { described_class.to_s.demodulize.underscore.to_sym }
  let(:order_factory) { :"bitex_#{order_type}" }
  let(:order_class) { "Bitex::#{order_type.capitalize}".constantize }
  let(:trade_type) { flow_factory.to_s.split('_').first.to_sym }
  let(:order_type) { { sell: :ask, buy: :bid }[trade_type] }

  describe '#active scope' do
    before(:each) { create_list(flow_factory, count_flows, status: status) }

    let(:count_flows) { Faker::Number.between(1, 10) }

    subject { described_class.active }

    context 'not finalised flows' do
      (described_class.statuses - %w[finalised]).each do |st|
        let(:status) { st }

        it "with status '#{st}'" do
          subject.count.should eq count_flows
        end
      end
    end

    context 'finalised flows' do
      let(:status) { :finalised }

      it { subject.count.should be_zero }
    end
  end

  describe '#old active' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: time_to_live)
      create_list(flow_factory, count_flows, status: :executing, created_at: timestamp.seconds.ago.to_time)
    end

    let(:count_flows) { Faker::Number.between(1, 10) }
    let(:time_to_live) { Faker::Number.between(30, 59) }

    subject { described_class.old_active }

    context 'active and old' do
      let(:timestamp) { (time_to_live + 20) }

      it { subject.count.should eq count_flows }
    end

    context 'active but not old' do
      let(:timestamp) { (time_to_live - 20) }

      it { subject.count.should be_zero }
    end
  end

  context 'with maker' do
    before(:each) { BitexBot::Robot.stub(maker: BitexBot::Api::Bitex.new(build(:bitex_maker_settings))) }

    describe '#finalise!' do
      before(:each) { BitexBot::Robot.maker.stub(find: order) }

      let(:flow) { build(flow_factory) }
      let(:order) { build(order_factory, status: status) }

      subject { flow }

      context 'with cancelled or canceled order status' do
        let(:status) { %i[cancelled completed].sample }

        it 'hasn´t associated order' do
          subject.executing?.should be_truthy
          subject.finalised?.should be_falsey

          subject.finalise!

          subject.finalised?.should be_truthy
        end
      end

      context 'with settling order status' do
        before(:each) { BitexBot::Robot.maker.stub(:cancel) { order.tap { order.status = :cancelling } } }

        let(:status) { :settling }
        let(:finaliser_status) { %i[cancelled completed].sample }

        it 'can´t finalised yet, has associated order' do
          subject.executing?.should be_truthy
          subject.finalised?.should be_falsey

          subject.finalise!
          subject.settling?.should be_truthy
          subject.finalised?.should be_falsey
        end

        it 'can be finalised, if then for any reason, order changes your status' do
          subject.executing?.should be_truthy
          subject.finalised?.should be_falsey

          subject.finalise!
          subject.settling?.should be_truthy
          subject.finalised?.should be_falsey

          order.status = finaliser_status
          subject.finalise!
          subject.settling?.should be_falsey
          subject.finalised?.should be_truthy
        end
      end
    end

    describe '#cancelled or completed, with order' do
      let(:flow) { build(flow_factory) }
      let(:order) { build(order_factory, status: status) }

      subject { flow.send(:cancelled_or_completed?, order) }

      context 'cancelled' do
        let(:status) { :cancelled }

        it { subject.should be_truthy }
      end

      context 'completed' do
        let(:status) { :completed }

        it { subject.should be_truthy }
      end

      context 'with any other status' do
        let(:status) { (order_class.statuses.values - %i[cancelled completed]).sample }

        it { subject.should be_falsey }
      end
    end

    describe '#do cancel' do
      before(:each) { BitexBot::Robot.maker.stub(:cancel) { order.tap { order.status = :cancelling } } }

      let(:order) { build(order_factory) }

      subject { build(flow_factory, status: status) }

      context 'with settling status' do
        let(:status) { :settling }

        it 'no change status' do
          subject.settling?.should be_truthy

          subject.send(:do_cancel, order)

          subject.settling?.should be_truthy
        end
      end

      context 'with any other status' do
        let(:status) { (described_class.statuses - %w[settling]).sample }

        it 'change status' do
          subject.send(:"#{status}?").should be_truthy

          subject.send(:do_cancel, order)

          subject.send(:"#{status}?").should be_falsey
          subject.settling?.should be_truthy
        end
      end
    end
  end

  describe '#do finalise' do
    subject { build(flow_factory, status: status) }

    context 'with finalised status' do
      let(:status) { :finalised }

      it 'no change status' do
        subject.finalised?.should be_truthy

        subject.send(:do_finalise)

        subject.finalised?.should be_truthy
      end
    end

    context 'with any other statyus' do
      let(:status) { (described_class.statuses - %w[finalised]).sample }

      it 'will always set finalised status' do
        subject.send(:"#{status}?").should be_truthy

        subject.send(:do_finalise)

        subject.send(:"#{status}?").should be_falsey
        subject.finalised?.should be_truthy
      end
    end
  end

  describe 'on work flow' do
    before(:each) { BitexBot::Robot.stub(maker: BitexBot::Api::Bitex.new(build(:bitex_maker_settings))) }

    let(:trade_factory) { :"bitex_#{trade_type}" }
    let(:open_trade_class) { "BitexBot::Open#{trade_type.capitalize}".constantize }

    let(:order_id) { 12_345 }

    context 'when fetching open positions' do
      before(:each) { stub_bitex_transactions }

      let(:flow) { create(flow_factory) }
      let(:trades) { described_class.sync_open_positions }
      let(:trade_id) { 12_345_678 }
      let(:other_trade_id) { 23_456 }

      it 'only gets its trades' do
        flow.order_id.should eq order_id

        expect do
          trades.size.should eq 1

          trades.sample.tap do |sample|
            sample.opening_flow.should eq flow
            sample.transaction_id.should eq trade_id
            sample.price.should eq 300
            sample.amount.should eq 600
            sample.quantity.should eq 2
          end
        end.to change { open_trade_class.count }.by(1)
      end

      it 'does not register the same inverse operation twice' do
        flow.order_id.should eq order_id

        described_class.sync_open_positions

        open_trade_class.count.should eq 1

        Timecop.travel(1.second.from_now)
        stub_bitex_transactions(build(trade_factory, id: other_trade_id))

        expect do
          trades.size.should eq 1
          trades.sample.transaction_id.should eq other_trade_id
        end.to change { open_trade_class.count }.by(1)
      end

      it 'does not register buys from another order book' do
        Bitex::Trade.stub(all: [build(trade_factory, id: other_trade_id, order_book: :btc_ars)])

        expect { described_class.sync_open_positions.should be_empty }.not_to change { open_trade_class.count }
        open_trade_class.count.should be_zero
      end

      it 'does not register buys from unknown bids' do
        expect { described_class.sync_open_positions.should be_empty }.not_to change { open_trade_class.count }
        open_trade_class.count.should be_zero
      end
    end
  end
end

shared_examples_for 'fails, when try place order on maker, but you do not have sufficient funds' do
  let(:flow_factory) { described_class.to_s.demodulize.underscore.to_sym }
  let(:order_factory) { :"bitex_#{order_type}" }
  let(:order_class) { "Bitex::#{order_type.capitalize}".constantize }
  let(:trade_type) { flow_factory.to_s.split('_').first.to_sym }
  let(:order_type) { { sell: :ask, buy: :bid }[trade_type] }

  let(:order) { build(order_factory, reason: :not_enough_funds) }
  let(:error) { 'You need to have %{maker_balance} on bitex to place this %{order_type}.' }
  let(:needed) { BitexBot::Settings.send("#{trade_type}ing").send("#{value_to_use}_per_order") }
  let(:value_to_use) { { sell: :quantity_to_sell, buy: :amount_to_spend }[trade_type] }

  it do
    expect do
      subject.should be_nil
      described_class.count.should be_zero
    end.to raise_exception(BitexBot::CannotCreateFlow, error % { maker_balance: needed, order_type: order_class })
  end
end

shared_examples_for 'fails, when creating any validation' do
  before(:each) { described_class.stub(:create!) { raise error } }

  let(:error) { Faker::Cannabis.health_benefit }

  it do
    expect do
      subject.should be_nil
      described_class.count.should be_zero
    end.to raise_exception(BitexBot::CannotCreateFlow, error)
  end
end
