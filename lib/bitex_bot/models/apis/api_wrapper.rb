module BitexBot
  module Api
    # This class represents the general behaviour for trading platform wrappers.
    class ApiWrapper
      MIN_AMOUNT = 5

      Transaction = Struct.new(
        :id,        # Integer
        :price,     # Decimal
        :amount,    # Decimal
        :timestamp, # Epoch Integer
        :raw        # Actual transaction
      )

      Order = Struct.new(
        :id,        # String
        :type,      # Symbol
        :price,     # Decimal
        :amount,    # Decimal
        :timestamp, # Integer
        :raw        # Actual order object
      ) do
        def method_missing(method_name, *args, &block)
          raw.respond_to?(method_name) ? raw.send(method_name, *args, &block) : super
        end

        def respond_to_missing?(method_name, include_private = false)
          raw.respond_to?(method_name) || super
        end
      end

      OrderBook = Struct.new(
        :timestamp, # Integer
        :bids,      # [OrderSummary]
        :asks       # [OrderSummary]
      )

      OrderSummary = Struct.new(
        :price,   # Decimal
        :quantity # Decimal
      )

      BalanceSummary = Struct.new(
        :btc, # Balance
        :usd, # Balance
        :fee  # Decimal
      )

      Balance = Struct.new(
        :total,    # Decimal
        :reserved, # Decimal
        :available # Decimal
      )

      UserTransaction = Struct.new(
        :order_id, # Integer
        :usd,      # Decimal
        :btc,      # Decimal
        :btc_usd,  # Decimal
        :fee,      # Decimal
        :type,     # Integer
        :timestamp # Epoch Integer
      )

      # @return [Array<Transaction>]
      def transactions
        raise 'self subclass responsibility'
      end

      # @return [OrderBook]
      def order_book(_retries = 20)
        raise 'self subclass responsibility'
      end

      # @return [BalanceSummary]
      def balance
        raise 'self subclass responsibility'
      end

      # @return [nil]
      def cancel
        raise 'self subclass responsibility'
      end

      # @return [Array<Order>]
      def orders
        raise 'self subclass responsibility'
      end

      # @return [UserTransaction]
      def user_transactions
        raise 'self subclass responsibility'
      end

      # @param type
      # @param price
      # @param quantity
      def place_order(type, price, quantity)
        order = send_order(type, price, quantity)
        return order unless order.nil? || order.id.nil?

        Robot.log(:debug, "Captured error when placing order on #{self.class}")
        # Order may have gone through and be stuck somewhere in Wrapper's pipeline.
        # We just sleep for a bit and then look for the order.
        20.times do
          Robot.sleep_for(10)
          order = find_lost(type, price, quantity)
          return order if order.present?
        end
        raise OrderNotFound, "Closing: #{type} order not found for #{quantity} BTC @ $#{price}. #{order}"
      end

      # Hook Method - arguments could not be used in their entirety by the subclasses
      def send_order(_type, _price, _quantity)
        raise 'self subclass responsibility'
      end

      # @param order_method [String] buy|sell
      # @param price [Decimal]
      #
      # Hook Method - arguments could not be used in their entirety by the subclasses
      def find_lost(_type, _price, _quantity)
        raise 'self subclass responsibility'
      end

      # From an order when you buy or sell, when you place an order and it matches, you can match more than one order.
      # @param order_id
      # @param transactions: all matches for a purchase or sale order.
      #
      # @return [Array<Decimal, Decimal>]
      def amount_and_quantity(_order_id, _transactions)
        raise 'self subclass responsibility'
      end

      def enough_order_size?(quantity, price)
        (quantity * price) > MIN_AMOUNT
      end
    end

    class OrderNotFound < StandardError; end
    class ApiWrapperError < StandardError; end
  end
end
