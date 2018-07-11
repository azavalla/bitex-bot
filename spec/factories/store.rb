FactoryBot.define do
  factory :store, class: BitexBot::Store do
    maker_crypto                       nil
    taker_crypto                       nil
    maker_fiat                         nil
    taker_fiat                         nil
    crypto_stop                        nil
    fiat_stop                          nil
    crypto_warning                     nil
    fiat_warning                       nil
    buying_amount_to_spend_per_order   nil
    buying_fx_rate                     nil
    buying_profit                      nil
    selling_quantity_to_sell_per_order nil
    selling_fx_rate                    nil
    selling_profit                     nil
    hold                               nil
    log                                nil
    last_warning                       nil
  end
end
