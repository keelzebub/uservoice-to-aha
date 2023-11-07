require 'json'
require 'faraday'
require 'awesome_print'
require 'ruby-limiter'

class UserVoiceApi
  def initialize(options = {})
    # create a rate-limited queue which allows 110 operations per minute
    @queue = Limiter::RateQueue.new(110, interval: 60, balanced: false) do
      p '-'*40
      p "Hit the UserVoice limit, waiting"
      p '-'*40
    end

    @host = "https://#{options[:subdomain]}.uservoice.com"
    @conn = connection
    @api_key = options[:api_key]
    @api_secret = options[:api_secret]
    @access_token = authenticate
  end

  def fetch_users(cursor = nil)
    params = {
      includes: 'crm_accounts',
      per_page: 100,
      sort: 'created_at',
      cursor: cursor,
    }

    get('/admin/users', params)
  end

  def fetch_suggestions(cursor = nil)
    params = {
      includes: 'categories,labels,statuses,internal_status_updates',
      per_page: 100,
      sort: 'created_at',
      cursor: cursor,
      state: '-deleted,-spam,closed',
    }

    get('/admin/suggestions', params)
  end

  def fetch_supporters(cursor = nil)
    params = {
      per_page: 100,
      sort: 'created_at',
      cursor: cursor,
    }

    get('/admin/supporters', params)
  end

  def fetch_comments(cursor = nil)
    params = {
      per_page: 100,
      sort: 'updated_at',
      cursor: cursor
    }

    get('/admin/comments', params)
  end

  def fetch_feedback_records(cursor = nil)
    params = {
      per_page: 100,
      sort: 'created_at',
      cursor: cursor,
    }

    get('/admin/feedback_records', params)
  end

  private

  def authenticate
    # this operation will block until less than 110 shift calls have been made within the last minute
    @queue.shift

    body = {
      grant_type: 'client_credentials',
      client_id: @api_key,
      client_secret: @api_secret,
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
    # this operation will block until less than 110 shift calls have been made within the last minute
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
    rescue => e
      handle_error(e)
    else
      JSON.parse(response.body, symbolize_names: true)
    end
  end

  def post(route, body = nil)
    # this operation will block until less than 110 shift calls have been made within the last minute
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
    rescue => e
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



