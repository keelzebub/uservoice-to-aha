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

if !File.exists?('./tmp/created_contacts.csv')
  p 'You need to run migrate_contacts.rb first.'
  return
end

columns = [
  {
    name: 'uv_id',
    value: -> (item, _) { item[:id] }
  },
  {
    name: 'title',
    value: -> (item, _) { item[:title] }
  },
  {
    name: 'body',
    value: -> (item, _) { item[:body] }
  },
  {
    name: 'created_at',
    value: -> (item, _) { item[:created_at] }
  },
  {
    name: 'updated_at',
    value: -> (item, _) { item[:updated_at] }
  },
  {
    name: 'state',
    value: -> (item, _) { item[:state] }
  },
  {
    name: 'category',
    value: -> (item, included_items) { included_items[:categories][item[:links][:category]] }
  },
  {
    name: 'labels',
    value: -> (item, included_items) { (item[:links][:labels] || []).map { |label_id| included_items[:labels][label_id] }.join(',') }
  }
]

included_items = [
  {
    name: :categories,
    key: :id,
    value: :name
  },
  {
    name: :labels,
    key: :id,
    value: :name
  }
]

Utilities.create_uv_csv(uv_api, :suggestions, columns, {included_items: included_items})
p 'Suggestions fetched from UserVoice'