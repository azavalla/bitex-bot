module BitexStubs
  mattr_accessor(:bids) { {} }
  mattr_accessor(:asks) { {} }
  mattr_accessor(:active_bids) { {} }
  mattr_accessor(:active_asks) { {} }

  def stub_bitex_orders
    Bitex::Order.stub(:all) { BitexStubs.active_bids + BitexStubs.active_asks }

    Bitex::Bid.stub(:find) { |id| BitexStubs.bids[id] }

    Bitex::Ask.stub(:find) { |id| BitexStubs.asks[id] }

    Bitex::Bid.stub(:create!) do |order_book, to_spend, price|
      order_book.should eq BitexBot::Settings.bitex.order_book

      Bitex::Bid.new.tap do |bid|
        bid.id = 12_345
        bid.created_at = Time.now
        bid.price = price
        bid.amount = to_spend
        bid.remaining_amount = to_spend
        bid.status = :executing
        bid.order_book = order_book
        bid.stub(:cancel!) do
          bid.tap do |b|
            b.status = :cancelled
            BitexStubs.active_bids.delete(b.id)
          end
        end
        BitexStubs.bids[bid.id] = bid
        BitexStubs.active_bids[bid.id] = bid
      end
    end

    Bitex::Ask.stub(:create!) do |order_book, to_sell, price|
      order_book.should eq BitexBot::Settings.bitex.order_book

      Bitex::Ask.new.tap do |ask|
        ask.id = 12_345
        ask.created_at = Time.now
        ask.price = price
        ask.quantity = to_sell
        ask.remaining_quantity = to_sell
        ask.status = :executing
        ask.order_book = order_book
        ask.stub(:cancel!) do
          ask.tap do |a|
            a.status = :cancelled
            BitexStubs.active_asks.delete(a.id)
          end
        end
        BitexStubs.asks[ask.id] = ask
        BitexStubs.active_asks[ask.id] = ask
      end
    end
  end

  def stub_bitex_transactions(*extra_transactions)
    Bitex::Trade.stub(all: extra_transactions + [build(:bitex_buy), build(:bitex_sell)])
  end
end
