require 'spec_helper'

describe 'BitexApiWrapper' do
  before(:each) { BitexBot::Robot.setup }

  it 'Sends User-Agent header' do
    stub_stuff =
      stub_request(:get, 'https://bitex.la/api-v1/rest/private/profile?api_key=your_bitex_api_key_which_should_be_kept_safe')
        .with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    expect { Bitex::Profile.get }.to raise_exception(StandardError)
    stub_stuff.should have_been_requested
  end
end
