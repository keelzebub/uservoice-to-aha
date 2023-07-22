require 'awesome_print'
require './lib/aha_api.rb'
require './lib/uservoice_api.rb'
require './lib/utilities.rb'

include Utilities

# Initialize UserVoice
uv_options = {
  api_key: ENV['UV_API_KEY'],
  api_secret: ENV['UV_API_SECRET'],
  subdomain: ENV['UV_SUBDOMAIN'],
}
uv_api = UserVoiceApi.new(uv_options)

# Initialize Aha
aha_options = {
  api_key: ENV['AHA_API_KEY'],
  subdomain: ENV['AHA_SUBDOMAIN'],
}
aha_api = AhaApi.new(aha_options)

if !File.exists?('./tmp/org_fetch_status.tmp')
  Utilities.create_aha_organizations_csv(aha_api)
else
  p 'Organizations already fetched from Aha'
end

# Check if we left off somewhere (contact lists are long)
columns = [
  {
    name: 'email',
    value: -> (item, _) { item[:email_address] }
  },
  {
    name: 'first_name',
    value: -> (item, _) { (item[:name] || '').split(' ')[0] }
  },
  {
    name: 'last_name',
    value: -> (item, _) { first_name, *last_name = (item[:name] || '').split(' '); last_name.join(' ') }
  },
  {
    name: 'sf_id',
    value: -> (item, included_items) { included_items[:crm_accounts][item[:links][:crm_account]] }
  }
]

included_items = [
  {
    name: :crm_accounts,
    key: :id,
    value: :external_id
  }
]

skip_user = -> (item) { item[:supported_suggestions_count] == 0 }

Utilities.create_uv_csv(uv_api, :users, columns, {skip_option: skip_user, included_items: included_items})
p 'Contacts fetched from UserVoice'

# p 'Starting creation of Aha Idea users'
# Utilities.create_aha_contacts(aha_api, ENV['AHA_IDEA_PORTAL_ID'])