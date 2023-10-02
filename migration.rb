require 'awesome_print'
require 'yaml'

require './lib/aha_api.rb'
require './lib/aha_utilities.rb'
require './lib/uservoice_api.rb'
require './lib/uservoice_utilities.rb'

include AhaUtilities
include UserVoiceUtilities

config = YAML.load_file("./config.yml")

# Initialize UserVoice
uv_options = {
  api_key: config['uv_api_key'],
  api_secret: config['uv_api_secret'],
  subdomain: config['uv_subdomain'],
}
uv_api = UserVoiceApi.new(uv_options)

# Initialize Aha
aha_options = {
  api_key: config['aha_api_key'],
  subdomain: config['aha_subdomain'],
}
aha_api = AhaApi.new(aha_options)

if !File.exists?('./tmp/org_fetch_status.tmp')
  p 'Fetching organizations from Aha'
  Utilities.create_aha_organizations_csv(aha_api)
else
  p 'Organizations already fetched from Aha'
end

p 'Fetching users from UserVoice'
# UserVoiceUtilities.create_uv_users_csv(uv_api)
p 'Users fetched from UserVoice'

p 'Fetching suggestions from UserVoice'
# UserVoiceUtilities.create_uv_suggestions_csv(uv_api)
p 'Suggestions fetched from UserVoice'

p 'Fetching supporters from UserVoice'
# UserVoiceUtilities.create_uv_supporters_csv(uv_api)
p 'Supporters fetched from UserVoice'

p 'Fetching comments from UserVoice'
# UserVoiceUtilities.create_uv_comments_csv(uv_api)
p 'Comments fetched from UserVoice'

p 'Fetching feedback records from UserVoice'
# UserVoiceUtilities.create_uv_feedback_records_csv(uv_api)
p 'Feedback records fetched from UserVoice'

p 'Starting creation of Aha users'
AhaUtilities.create_aha_contacts(aha_api, config['aha_idea_portal_id'])
p 'Finished creating Aha users'

p 'Starting creation of Aha ideas'
AhaUtilities.create_aha_ideas(aha_api, config['aha_product_id'])
p 'Finished creating Aha ideas'

p 'Starting creation of Aha idea comments'
AhaUtilities.create_aha_comments(aha_api)
p 'Finished creating Aha comments'

p 'Starting creation of Aha endorsements (votes)'
AhaUtilities.create_aha_endorsements(aha_api)
p 'Finished creating Aha endorsements (votes)'

p 'Starting creation of Aha proxy endorsements (proxy votes)'
AhaUtilities.create_aha_proxy_endorsements(aha_api)
p 'Finished creating Aha proxy endorsements (proxy votes)'