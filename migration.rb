require 'awesome_print'
require 'yaml'

require './lib/uservoice_api.rb'
require './lib/uservoice_utilities.rb'
require './lib/aha_api.rb'
require './lib/salesforce_api.rb'
require './lib/migration_utilities.rb'

include UserVoiceUtilities
include MigrationUtilities

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
  sf_integration_id: config['aha_sf_integration_id'],
}
aha_api = AhaApi.new(aha_options)

# Initialize Salesforce
sf_options = {
  access_token: config['sf_access_token'],
  subdomain: config['sf_subdomain'],
}
sf_api = SalesforceApi.new(sf_options)

if !File.exists?('./tmp/org_fetch_status.tmp')
  p 'Fetching organizations from Aha'
  Utilities.create_aha_organizations_csv(aha_api)
else
  p 'Organizations already fetched from Aha'
end

p 'Fetching users from UserVoice'
# user_count = UserVoiceUtilities.create_uv_users_csv(uv_api)

p 'Fetching non-deleted and non-spam suggestions from UserVoice'
# suggestion_count = UserVoiceUtilities.create_uv_suggestions_csv(uv_api)

p 'Fetching supporters (votes) from UserVoice'
# supporter_count = UserVoiceUtilities.create_uv_supporters_csv(uv_api)

p 'Fetching comments from UserVoice'
# comment_count = UserVoiceUtilities.create_uv_comments_csv(uv_api)

p 'Fetching feedback records (proxy votes) from UserVoice'
# feedback_record_count = UserVoiceUtilities.create_uv_feedback_records_csv(uv_api)

p 'Starting creation of Aha users'
# MigrationUtilities.create_aha_contacts(aha_api, config['aha_idea_portal_id'])

p 'Starting creation of Aha ideas'
idea_creation_options = {
  category_map: config['suggestion_category_map'],
  status_map: config['suggestion_status_map'],
  default_status: config['aha_default_status'],
  default_category: config['aha_default_category'],
}

# MigrationUtilities.create_aha_sf_ideas(aha_api, sf_api, config['aha_product_id'], idea_creation_options)

p 'Starting creation of Aha idea comments'
# MigrationUtilities.create_aha_comments(aha_api)

p 'Starting creation of Aha endorsements (votes)'
# MigrationUtilities.create_aha_endorsements(aha_api)

p 'Starting creation of Aha proxy endorsements (proxy votes)'
# MigrationUtilities.create_aha_sf_proxy_endorsements(aha_api, sf_api, config['default_sf_user_id'], config['sf_subdomain'])

p 'Merge relevant Aha ideas together'
# merge_aha_ideas(aha_api)

p 'Migration complete!'