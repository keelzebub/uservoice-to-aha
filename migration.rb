require 'awesome_print'
require './lib/uservoice_api.rb'

# Authenticate with UserVoice
@uv_api = UserVoiceApi.new

def fetch_users(cursor = nil)
  users_params = {
    includes: 'crm_accounts',
    per_page: 100,
    sort: 'created_at',
    cursor: cursor,
  }

  users_response = @uv_api.get('/admin/users', users_params)

  valid_users = users_response[:users].map do |user|
    if user[:supported_suggestions_count] > 0
      user
    end
  end.compact

  {
    cursor: cursor,
    users: valid_users,
  }

end

fetch_users