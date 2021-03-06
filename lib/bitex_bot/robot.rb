trap 'INT' do
  if BitexBot::Robot.graceful_shutdown
    print "\b"
    BitexBot::Robot.log(:info, "Ok, ok, I'm out.")
    exit 1
  end
  BitexBot::Robot.graceful_shutdown = true
  BitexBot::Robot.log(:info, "Shutting down as soon as I've cleaned up.")
end

module BitexBot
  # Documentation here!
  # rubocop:disable Metrics/ClassLength
  class Robot
    extend Forwardable

    cattr_accessor :taker

    cattr_accessor :graceful_shutdown
    cattr_accessor :cooldown_until
    cattr_accessor(:current_cooldowns) { 0 }

    cattr_accessor(:logger) do
      logdev = Settings.log.try(:file)
      STDOUT.sync = true unless logdev.present?
      Logger.new(logdev || STDOUT, 10, 10_240_000).tap do |log|
        log.level = Logger.const_get(Settings.log.level.upcase)
        log.formatter = proc do |severity, datetime, _progname, msg|
          date = datetime.strftime('%m/%d %H:%M:%S.%L')
          "#{format('%-6s', severity)} #{date}: #{msg}\n"
        end
      end
    end

    def self.setup
      Bitex.api_key = Settings.maker_settings.api_key
      Bitex.sandbox = Settings.maker_settings.sandbox
      self.taker = Settings.taker_class.tap { |klass| klass.setup(Settings.taker_settings) }
    end

    # Trade constantly respecting cooldown times so that we don't get banned by api clients.
    def self.run!
      bot = start_robot
      self.cooldown_until = Time.now
      loop do
        start_time = Time.now
        next if start_time < cooldown_until

        self.current_cooldowns = 0
        bot.trade!
        self.cooldown_until = start_time + current_cooldowns.seconds
      end
    end

    def self.sleep_for(seconds)
      sleep(seconds)
    end
    def_delegator self, :sleep_for

    def self.log(level, message)
      logger.send(level, message)
    end
    def_delegator self, :log

    def self.with_cooldown
      yield.tap do
        self.current_cooldowns += 1
        sleep_for(0.1)
      end
    end

    def self.start_robot
      setup
      log(:info, 'Loading trading robot, ctrl+c *once* to exit gracefully.')
      new
    end

    # rubocop:disable Metrics/AbcSize
    def trade!
      sync_opening_flows if active_opening_flows?
      finalise_some_opening_flows
      shutdown! if shutdable?
      start_closing_flows if open_positions?
      sync_closing_flows if active_closing_flows?
      start_opening_flows_if_needed
    rescue CannotCreateFlow => e
      notify("#{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 3)
    rescue Curl::Err::TimeoutError => e
      log(:error, "#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep_for(15)
    rescue OrderNotFound => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
    rescue ApiWrapperError => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
    rescue OrderArgumentError => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
    rescue StandardError => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 2)
    end
    # rubocop:enable Metrics/AbcSize

    def active_closing_flows?
      [BuyClosingFlow, SellClosingFlow].map(&:active).any?(&:exists?)
    end

    def active_opening_flows?
      [BuyOpeningFlow, SellOpeningFlow].map(&:active).any?(&:exists?)
    end

    # The trader has a Store
    def store
      @store ||= Store.first || Store.create
    end

    private

    def with_cooldown(&block)
      self.class.with_cooldown(&block)
    end

    def sync_opening_flows
      [SellOpeningFlow, BuyOpeningFlow].each(&:sync_open_positions)
    end

    def shutdable?
      !(active_flows? || open_positions?) && turn_off?
    end

    def shutdown!
      log(:info, 'Shutdown completed')
      exit
    end

    def active_flows?
      active_opening_flows? || active_closing_flows?
    end

    def turn_off?
      self.class.graceful_shutdown
    end

    def finalise_some_opening_flows
      [BuyOpeningFlow, SellOpeningFlow].each { |kind| active_flows(kind).each(&:finalise!) }
    end

    def active_flows(opening_flow_class)
      turn_off? ? opening_flow_class.active : opening_flow_class.old_active
    end

    def start_closing_flows
      [BuyClosingFlow, SellClosingFlow].each(&:close_open_positions)
    end

    def open_positions?
      [OpenBuy, OpenSell].map(&:open).any?(&:exists?)
    end

    def sync_closing_flows
      orders = with_cooldown { Robot.taker.orders }
      transactions = with_cooldown { Robot.taker.user_transactions }

      [BuyClosingFlow, SellClosingFlow].each do |kind|
        kind.active.each { |flow| flow.sync_closed_positions(orders, transactions) }
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def start_opening_flows_if_needed
      return log(:debug, 'Not placing new orders because of hold') if store.reload.hold?
      return log(:debug, 'Not placing new orders, closing flows.') if active_closing_flows?
      return log(:debug, 'Not placing new orders, shutting down.') if turn_off?

      recent_buying, recent_selling = recent_operations
      return log(:debug, 'Not placing new orders, recent ones exist.') if recent_buying && recent_selling

      profile = Bitex::Profile.get
      taker_balance = with_cooldown { Robot.taker.balance }
      sync_log_and_store(taker_balance, profile)

      check_balance_warning if expired_last_warning?

      return log(:debug, "Not placing new orders, #{Settings.quote} target not met") if alert?(:fiat, :stop)
      return log(:debug, "Not placing new orders, #{Settings.base} target not met") if alert?(:crypto, :stop)

      order_book = with_cooldown { Robot.taker.order_book }
      transactions = with_cooldown { Robot.taker.transactions }

      create_buy_opening_flow(taker_balance, order_book, transactions, profile) unless recent_buying
      create_sell_opening_flow(taker_balance, order_book, transactions, profile) unless recent_selling
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def recent_operations
      [BuyOpeningFlow, SellOpeningFlow].map do |kind|
        threshold = (Settings.time_to_live / 2).seconds.ago
        kind.active.where('created_at > ?', threshold).first
      end
    end

    def sync_log_and_store(taker_balance, maker_balance)
      file = Settings.log.try(:file)
      last_log = `tail -c 61440 #{file}` if file.present?

      store.update(
        maker_fiat: maker_balance[:"#{Settings.quote}_balance"], maker_crypto: maker_balance[:"#{Settings.base}_balance"],
        taker_fiat: taker_balance.fiat.total, taker_crypto: taker_balance.crypto.total,
        log: last_log
      )
    end

    def expired_last_warning?
      store.last_warning.nil? || store.last_warning < 30.minutes.ago
    end

    def check_balance_warning
      notify_balance_warning(Settings.base, balance(:crypto), store.crypto_warning) if alert?(:crypto, :warning)
      notify_balance_warning(Settings.quote, balance(:fiat), store.fiat_warning) if alert?(:fiat, :warning)
    end

    def alert?(currency, flag)
      return unless store.send("#{currency}_#{flag}").present?
      balance(currency) <= store.send("#{currency}_#{flag}")
    end

    def balance(currency)
      fx_rate = currency == :fiat ? Settings.buying_fx_rate : 1
      store.send("maker_#{currency}") / fx_rate + store.send("taker_#{currency}")
    end

    def notify_balance_warning(currency, amount, warning_amount)
      notify("#{currency.upcase} balance is too low, it's #{amount}, make it #{warning_amount} to stop this warning.")
      store.update(last_warning: Time.now)
    end

    def notify(message, subj = 'Notice from your robot trader')
      log(:error, message)
      return unless Settings.mailer.present?

      new_mail(subj, message).tap do |mail|
        mail.delivery_method(Settings.mailer.delivery_method.to_sym, Settings.mailer.options.to_hash)
      end.deliver!
    end

    def new_mail(subj, message)
      Mail.new do
        from Settings.mailer.from
        to Settings.mailer.to
        subject subj
        body message
      end
    end

    def create_buy_opening_flow(balance, order_book, transactions, profile)
      BuyOpeningFlow.create_for_market(balance.crypto.available, order_book.bids, transactions, profile[:fee], balance.fee, store)
    end

    def create_sell_opening_flow(balance, order_book, transactions, profile)
      SellOpeningFlow.create_for_market(balance.fiat.available, order_book.asks, transactions, profile[:fee], balance.fee, store)
    end
    # rubocop:enable Metrics/ClassLength
  end
end
