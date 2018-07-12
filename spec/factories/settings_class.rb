FactoryBot.define do
  factory :bitex_taker, class: BitexBot::SettingsClass do
    bitex { build(:bitex_taker_settings) }
  end

  factory :bitex_taker_settings, class: BitexBot::SettingsClass do
    sequence(:api_key)   { |n| "api_key_#{n}" }
    ssl_version          nil
    debug                false
    sandbox              false
  end

  factory :bitstamp_taker, class: BitexBot::SettingsClass do
    bitstamp { build(:bitstamp_taker_settings) }
  end

  factory :bitstamp_taker_settings, class: BitexBot::SettingsClass do
    sequence(:api_key)   { |n| "api_key_#{n}" }
    sequence(:secret)    { |n| "secret_#{n}" }
    sequence(:client_id) { |n| "client_id_#{n}" }
  end

  factory :itbit_taker, class: BitexBot::SettingsClass do
    itbit { build(:itbit_taker_settings) }
  end

  factory :itbit_taker_settings, class: BitexBot::SettingsClass do
    sequence(:client_key)        { |n| "client_key_#{n}" }
    sequence(:secret)            { |n| "secret_#{n}" }
    sequence(:user_id)           { |n| "user_id_#{n}" }
    sequence(:default_wallet_id) { |n| "wallet_00#{n}" }
    sandbox                      false
  end

  factory :kraken_taker, class: BitexBot::SettingsClass do
    kraken { build(:kraken_taker_settings) }
  end

  factory :kraken_taker_settings, class: BitexBot::SettingsClass do
    sequence(:api_key)    { |n| "api_key_#{n}" }
    sequence(:api_secret) { |n| "api_secret_#{n}" }
  end

  factory :buying_settings, class: BitexBot::SettingsClass do
    amount_to_spend_per_order 10.to_d
    profit                    0.5.to_d
    fx_rate                   1.to_d
  end

  factory :selling_settings, class: BitexBot::SettingsClass do
    quantity_to_sell_per_order 0.1.to_d
    profit                     0.5.to_d
    fx_rate                    1.to_d
  end

  factory :log_settings, class: BitexBot::SettingsClass do
    file  'bitex_bot.log'
    level :info
  end

  factory :database_settings, class: BitexBot::SettingsClass do
    adapter  :sqlite3
    database 'bitex_bot.db'
  end

  factory :mailer_settings, class: BitexBot::SettingsClass do
    from            'robot@example.com'
    to              'you@example.com'
    delivery_method :smtp
    options         build(:mailer_options_settings)
  end

  factory :mailer_options_settings, class: BitexBot::SettingsClass do
    address              'your_smtp_server_address.com'
    port                 587
    authentication       'plain'
    enable_starttls_auto true
    user_name            'your_user_name'
    password             'your_smtp_password'
  end
end
