module BitexBot
  # Any arbitrage workflow has 2 stages, opening positions and then closing them.
  # The OpeningFlow stage places an order on bitex, detecting and storing all transactions spawn from that order as
  # Open positions.
  class OpeningFlow < ActiveRecord::Base
    extend Forwardable

    self.abstract_class = true

    # The updated config store as passed from the robot
    cattr_accessor :store

    # @!group Statuses
    # All possible flow statuses
    # @return [Array<String>]
    def self.statuses
      %w[executing settling finalised]
    end

    def self.active
      where.not(status: :finalised)
    end

    def self.old_active
      active.where('created_at < ?', Settings.time_to_live.seconds.ago)
    end
    # @!endgroup

    # This use hooks methods, these must be defined in the subclass:
    #   #maker_price
    #   #order_class
    #   #remote_value_to_use
    #   #safest_price
    #   #value_to_use
    # rubocop:disable Metrics/AbcSize
    def self.create_for_market(remote_balance, taker_orders, taker_transactions, maker_fee, taker_fee, store)
      self.store = store

      remote_value, safest_price = calc_remote_value(maker_fee, taker_fee, taker_orders, taker_transactions)
      raise CannotCreateFlow, "Needed #{remote_value} but you only have #{remote_balance}" unless
        enough_remote_funds?(remote_balance, remote_value)

      bitex_price = maker_price(remote_value)
      order = create_order!(bitex_price)
      raise CannotCreateFlow, "You need to have #{value_to_use} on bitex to place this #{order_class.name}." unless
        enough_funds?(order)

      Robot.log(
        :info,
        "Opening: Placed #{order_class.name} ##{order.id} #{value_to_use} @ #{Settings.quote.upcase} #{bitex_price}"\
        " (#{remote_value})"
      )

      create!(
        price: bitex_price,
        value_to_use: value_to_use,
        suggested_closing_price: safest_price,
        status: 'executing',
        order_id: order.id
      )
    rescue StandardError => e
      raise CannotCreateFlow, e.message
    end
    # rubocop:enable Metrics/AbcSize

    def self.calc_remote_value(maker_fee, taker_fee, taker_orders, taker_transactions)
      value_to_use_needed = (value_to_use + maker_plus(maker_fee)) / (1 - taker_fee / 100)
      safest_price = safest_price(taker_transactions, taker_orders, value_to_use_needed)
      remote_value = remote_value_to_use(value_to_use_needed, safest_price)

      [remote_value, safest_price]
    end

    def self.create_order!(bitex_price)
      Robot.maker.create_order!(order_class, Settings.maker_settings.order_book, value_to_use, bitex_price, true)
    rescue StandardError => e
      raise CannotCreateFlow, e.message
    end

    def self.enough_funds?(order)
      !order.reason.to_s.inquiry.not_enough_funds?
    end

    def self.enough_remote_funds?(remote_balance, remote_value)
      remote_balance >= remote_value
    end

    def self.maker_plus(fee)
      value_to_use * fee / 100
    end

    # Buys on bitex represent open positions, we mirror them locally so that we can plan on how to close them.
    # This use hooks methods, these must be defined in the subclass:
    #   #transaction_order_id(transaction) => [Sell: ask_id | Buy: bid_id]
    #   #open_position_class => [Sell: OpenSell | Buy: OpenBuy]
    def self.sync_open_positions
      threshold = open_position_class.order('created_at DESC').first.try(:created_at)
      Robot.maker.transactions.map do |transaction|
        next unless sought_transaction?(threshold, transaction)

        flow = find_by_order_id(transaction_order_id(transaction))
        next unless flow.present?

        create_open_position!(transaction, flow)
      end.compact
    end

    # sync_open_positions helpers
    def self.create_open_position!(transaction, flow)
      Robot.log(
        :info,
        "Opening: #{name} ##{flow.id} was hit for #{transaction.raw.quantity} #{Settings.base.upcase} @ #{Settings.quote.upcase}"\
        " #{transaction.price}"
      )

      open_position_class.create!(
        transaction_id: transaction.id,
        price: transaction.price,
        amount: transaction.amount,
        quantity: transaction.raw.quantity,
        opening_flow: flow
      )
    end

    def self.sought_transaction?(threshold, transaction)
      fit_operation_kind?(transaction) &&
        !expired_transaction?(transaction, threshold) &&
        !open_position?(transaction) &&
        expected_order_book?(transaction)
    end

    def self.fit_operation_kind?(transaction)
      transaction.raw.is_a?(transaction_class)
    end

    def self.expired_transaction?(transaction, threshold)
      threshold.present? && transaction.timestamp < (threshold - 30.minutes).to_i
    end

    def self.open_position?(transaction)
      open_position_class.find_by_transaction_id(transaction.id)
    end

    def self.expected_order_book?(transaction)
      transaction.raw.order_book == Settings.maker_settings.order_book
    end

    def self.transaction_order_id(_transaction)
      raise SubclassResponsibility
    end

    def self.open_position_class
      raise SubclassResponsibility
    end

    def self.transaction_class
      raise SubclassResponsibility
    end

    def self.maker_price(_amount_to_reverse_trade)
      raise SubclassResponsibility
    end

    def self.order_class
      raise SubclassResponsibility
    end

    def self.profit
      raise SubclassResponsibility
    end

    def self.remote_value_to_use(_value_to_use_needed, _safest_price)
      raise SubclassResponsibility
    end

    def self.safest_price(_taker_transactions, _taker_orders, _amount_to_use)
      raise SubclassResponsibility
    end

    def self.value_to_use
      raise SubclassResponsibility
    end

    validates :status, presence: true, inclusion: { in: statuses }
    validates_presence_of :order_id, :price, :value_to_use

    # Statuses:
    #   executing: The Bitex order has been placed, its id stored as order_id.
    #   setting: In process of cancelling the Bitex order and any other outstanding order in the other exchange.
    #   finalised: Successfully settled or finished executing.
    statuses.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
      define_method("#{status_name}!") { update!(status: status_name) }
    end

    def finalise!
      order = Robot.maker.find(order_class, order_id)
      cancelled_or_completed?(order) ? do_finalise : do_cancel(order)
    end

    private

    def cancelled_or_completed?(order)
      %i[cancelled completed].any? { |status| order.status == status }
    end

    def do_finalise
      Robot.log(:info, "Opening: #{order_class.name} ##{order_id} finalised.")
      finalised!
    end

    def do_cancel(order)
      Robot.log(:info, "Opening: #{order_class.name} ##{order_id} canceled.")
      Robot.maker.cancel(order)
      settling! unless settling?
    end
  end

  class CannotCreateFlow < StandardError; end
  class SubclassResponsibility < StandardError; end
end
