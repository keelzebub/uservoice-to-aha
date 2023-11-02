require 'json'
require 'faraday'
require 'awesome_print'
require 'ruby-limiter'

class SalesforceApi
  def initialize(options = {})
    # create a rate-limited queue which allows 110 operations per minute
    @queue = Limiter::RateQueue.new(110, interval: 60, balanced: false) do
      p '-'*40
      p "Hit the Salesforce limit, waiting"
      p '-'*40
    end

    @host = "https://#{options[:subdomain]}.my.salesforce.com"
    @access_token = options[:access_token]
    @conn = connection
  end

  def create_idea(params)
    post('/sobjects/ahaapp__AhaIdea__c', params)
  end

  def fetch_user_id(email)
    response = get('/query', {q: "SELECT email, id FROM User WHERE email = '#{email}'"})

    if response[:records].length > 0
      response[:records][0][:Id]
    else
      nil
    end
  end

  def fetch_org_name(id)
    response = get('/query', {q: "SELECT name, id FROM Account WHERE Id = '#{id}'"})

    if response[:records].length > 0
      response[:records][0][:Name]
    else
      nil
    end
  end

  def create_aha_idea_link(params)
    post('/sobjects/ahaapp__AhaIdeaLink__c', params)
  end

  private

  def connection
    Faraday.new(url: @host) do |faraday|
      faraday.request :url_encoded
      faraday.response :raise_error
    end
  end

  def get(route, url_params = nil)
    # this operation will block until less than 110 shift calls have been made within the last minute
    @queue.shift

    begin
      response = @conn.get("/services/data/v58.0#{route}") do |req|
        req.params = url_params
        req.headers['Authorization'] = "Bearer #{@access_token}" if !@access_token.nil?
        req.headers['Content-Type'] = "application/json"
      end
    rescue Faraday::ClientError => e
      handle_error(e)
    else
      JSON.parse(response.body, symbolize_names: true)
    end
  end

  def post(route, body = nil)
    # this operation will block until less than 110 shift calls have been made within the last minute
    @queue.shift

    begin
      response = @conn.post("/services/data/v58.0#{route}") do |req|
        req.body = body.to_json
        req.headers['Authorization'] = "Bearer #{@access_token}" if !@access_token.nil?
        req.headers['Content-Type'] = "application/json"
      end
    rescue Faraday::ClientError => e
      handle_error(e)
    else
      JSON.parse(response.body, symbolize_names: true)
    end
  end

  def handle_error(e)
    p '-'*40
    p "Error: #{e.response[:status]}"
    ap e.response
    p '-'*40
    raise 'error'
  end
end



