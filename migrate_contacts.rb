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

if !File.exists?('./tmp/progress.tmp')
  Utilities.create_aha_organizations_csv(aha_api)
else
  p 'Organizations already fetched from Aha'
end

# Check if we left off somewhere (contact lists are long)
Utilities.create_uv_contacts_csv(uv_api)
p 'Contacts fetched from UserVoice'

