shared_examples_for BitexBot::Api::Wrapper do
  let(:wrapper_name) { described_class.name.demodulize.downcase.to_sym }

  it 'Sends User-Agent header' do
    stub_stuff

    # we don't care about the response
    expect { wrapper.send(stuff_method) }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end

  it '#balance' do
    send("stub_#{wrapper_name}_balance")

    balance = wrapper.balance
    balance.should be_a(BitexBot::Api::BalanceSummary)
    balance.members.should contain_exactly(*%i[crypto fiat fee])

    balance.crypto.should be_a(BitexBot::Api::Balance)
    balance.fiat.should be_a(BitexBot::Api::Balance)
    balance.fee.should be_a(BigDecimal)

    [balance.crypto, balance.fiat].all? do |sample|
      sample.members.should contain_exactly(*%i[total reserved available])

      sample.total.should be_a(BigDecimal)
      sample.reserved.should be_a(BigDecimal)
      sample.available.should be_a(BigDecimal)
    end
  end

  it '#cancel' do
    send("stub_#{wrapper_name}_orders")

    wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    send("stub_#{wrapper_name}_order_book")

    order_book = wrapper.order_book
    order_book.should be_a(BitexBot::Api::OrderBook)
    order_book.members.should contain_exactly(*%i[bids asks timestamp])

    order_book.bids.should be_a(Array)
    order_book.asks.should be_a(Array)
    order_book.timestamp.should be_a(Integer)

    [order_book.bids.sample, order_book.asks.sample].all? do |sample|
      sample.should be_a(BitexBot::Api::OrderSummary)
      sample.members.should contain_exactly(*%i[price quantity])

      sample.price.should be_a(BigDecimal)
      sample.quantity.should be_a(BigDecimal)
    end
  end

  it '#orders' do
    send("stub_#{wrapper_name}_orders")

    wrapper.orders.should be_a(Array)

    sample = wrapper.orders.sample
    sample.should be_a(BitexBot::Api::Order)
    sample.members.should contain_exactly(*%i[id type price amount timestamp raw])

    sample.id.should be_a(String)
    sample.type.should be_a(Symbol)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    raw_order_classes.should include(sample.raw.class)
  end

  it '#transactions' do
    send("stub_#{wrapper_name}_transactions")

    wrapper.transactions.should be_a(Array)

    sample = wrapper.transactions.sample
    sample.should be_a(BitexBot::Api::Transaction)
    sample.members.should contain_exactly(*%i[id price amount timestamp raw])

    sample.id.should be_a(Integer)
    sample.price.should be_a(BigDecimal)
    sample.amount.should be_a(BigDecimal)
    sample.timestamp.should be_a(Integer)
    raw_transaction_classes.should include(sample.raw.class)
  end

  it '#find_lost' do
    send("stub_#{wrapper_name}_orders")

    sample = wrapper.orders.sample
    wrapper.find_lost(sample.type, sample.price, sample.amount).present?
  end
end
