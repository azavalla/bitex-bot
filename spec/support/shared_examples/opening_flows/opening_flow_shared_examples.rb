shared_examples_for BitexBot::OpeningFlow do
  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(described_class.statuses)) }

  let(:factory) { described_class.to_s.demodulize.underscore.to_sym }

  describe '#active scope' do
    before(:each) { create_list(factory, count_flows, status: status) }
    let(:count_flows) { Faker::Number.between(1, 10) }

    context 'not finalized flows' do
      (described_class.statuses - ['finalised']).each do |st|
        let(:status) { st }

        it "with status '#{st}'" do
          described_class.active.count.should eq count_flows 
        end
      end
    end

    context 'finalized flows' do
      let(:status) { :finalised }

      it { described_class.active.count.should be_zero }
    end
  end

  describe '#old active scope' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: time_to_live)
      create_list(factory, count_flows, status: :executing, created_at: timestamp.seconds.ago.to_time)
    end

    let(:count_flows) { Faker::Number.between(1, 10) }
    let(:time_to_live) { Faker::Number.between(30, 59) }

    context 'active and old' do
      let(:timestamp) { (time_to_live + 20) }

      it { described_class.active.count.should eq count_flows }
    end

    context 'active but not old' do
      let(:timestamp) { (time_to_live - 20) }

      it { described_class.old_active.count.should be_zero }
    end
  end

  describe 'on work flow' do
    before(:each) { BitexBot::Robot.setup }

    let(:trade_name) { described_class.to_s.demodulize.underscore.split('_').first }
    let(:bitex_trade) { :"bitex_#{trade_name}" }
    let(:trade_class) { "BitexBot::Open#{trade_name.capitalize}".constantize }

    let(:order_id) { 12_345 }

    context 'when fetching open positions' do
      before(:each) { stub_bitex_transactions }

      let(:flow) { create(factory) }
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
        end.to change { trade_class.count }.by(1)
      end

      it 'does not register the same inverse operation twice' do
        flow.order_id.should eq order_id

        described_class.sync_open_positions

        trade_class.count.should eq 1

        Timecop.travel(1.second.from_now)
        stub_bitex_transactions(build(bitex_trade, id: other_trade_id))

        expect do
          trades.size.should eq 1
          trades.sample.transaction_id.should eq other_trade_id
        end.to change { trade_class.count }.by(1)
      end

      it 'does not register buys from another order book' do
        Bitex::Trade.stub(all: [build(bitex_trade, id: other_trade_id, order_book: :btc_ars)])

        expect { described_class.sync_open_positions.should be_empty }.not_to change { trade_class.count }
        trade_class.count.should be_zero
      end

      it 'does not register buys from unknown bids' do
        expect { described_class.sync_open_positions.should be_empty }.not_to change { trade_class.count }
        trade_class.count.should be_zero
      end
    end
  end
end
