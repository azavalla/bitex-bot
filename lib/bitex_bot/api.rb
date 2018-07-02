module BitexBot
  module Api
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
      :crypto, # Balance
      :fiat,   # Balance
      :fee     # Decimal
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
  end
end
