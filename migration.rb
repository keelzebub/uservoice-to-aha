require 'awesome_print'
require './lib/aha_api.rb'
require './lib/aha_utilities.rb'
require './lib/uservoice_api.rb'
require './lib/uservoice_utilities.rb'

include AhaUtilities
include UserVoiceUtilities

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
  p 'Fetching organizations from Aha'
  Utilities.create_aha_organizations_csv(aha_api)
else
  p 'Organizations already fetched from Aha'
end

p 'Fetching users from UserVoice'
UserVoiceUtilities.create_uv_users_csv(uv_api)
p 'Users fetched from UserVoice'


p 'Fetching suggestions from UserVoice'
UserVoiceUtilities.create_uv_suggestions_csv(uv_api)
p 'Suggestions fetched from UserVoice'



p 'Starting creation of Aha Idea users'
# AhaUtilities.create_aha_contacts(aha_api, ENV['AHA_IDEA_PORTAL_ID'])