require 'json'
require 'faraday'
require 'awesome_print'
require 'ruby-limiter'

class UserVoiceApi
  def initialize(options = {})
    # create a rate-limited queue which allows 120 operations per minute
    @queue = Limiter::RateQueue.new(120, interval: 60, balanced: false) do
      p '-'*40
      p "Hit the limit, waiting"
      p '-'*40
    end

    @host = "https://#{ENV['UV_SUBDOMAIN']}.uservoice.com"
    @conn = connection
    @access_token = authenticate
  end

  def authenticate
    # this operation will block until less than 120 shift calls have been made within the last minute
    @queue.shift

    body = {
      grant_type: 'client_credentials',
      client_id: ENV['UV_API_KEY'],
      client_secret: ENV['UV_API_SECRET']
    }

    response = post('/oauth/token', body)
    response[:access_token]
  end

  def connection
    Faraday.new(url: @host) do |faraday|
      faraday.request :url_encoded
      faraday.response :raise_error
    end
  end

  def get(route, url_params = nil)
    # this operation will block until less than 120 shift calls have been made within the last minute
    @queue.shift

    begin
      response = @conn.get("/api/v2#{route}") do |req|
        req.params = url_params
        req.headers['Authorization'] = "Bearer #{@access_token}"
      end
    rescue Faraday::UnauthorizedError => e
      @access_token = nil
      authenticate
      get(route, url_params)
    rescue Faraday::ClientError => e
      handle_error(e)
    else
      JSON.parse(response.body, symbolize_names: true)
    end
  end

  def post(route, body = nil)
    # this operation will block until less than 120 shift calls have been made within the last minute
    @queue.shift

    begin
      response = @conn.post("/api/v2#{route}") do |req|
        req.body = body
        req.headers['Authorization'] = "Bearer #{@access_token}" if !@access_token.nil?
      end
    rescue Faraday::UnauthorizedError => e
      @access_token = nil
      authenticate
      post(route, body)
    rescue Faraday::ClientError => e
      handle_error(e)
    else
      JSON.parse(response.body, symbolize_names: true)
    end
  end

  private

  def handle_error(e)
    p '-'*40
    p "Error: #{e.response[:status]}"
    ap e.response
    p '-'*40
    raise 'error'
  end
end



