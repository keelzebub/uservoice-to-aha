require 'awesome_print'
require './lib/uservoice_api.rb'

# Authenticate with UserVoice
uv_options = {
  api_key: ENV['UV_API_KEY'],
  api_secret: ENV['UV_API_SECRET'],
  subdomain: ENV['UV_SUBDOMAIN'],
}
uv_api = UserVoiceApi.new(uv_options)

ap uv_api.fetch_users