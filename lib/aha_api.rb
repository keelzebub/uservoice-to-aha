require 'json'
require 'faraday'
require 'awesome_print'
require 'ruby-limiter'

class AhaApi
  def initialize(options = {})
    # create a rate-limited queue which allows 290 operations per minute
    @queue = Limiter::RateQueue.new(290, interval: 60, balanced: true) do
      p '-'*40
      p "Hit the Aha limit, waiting"
      p '-'*40
    end

    @host = "https://#{options[:subdomain]}.aha.io"
    @conn = connection
    @api_key = options[:api_key]
  end

  def fetch_organizations(page)
    params = {
      page: page,
      per_page: 100,
      fields: 'name,custom_fields'
    }

    get('/idea_organizations', params)
  end

  def create_contact(params)
    post('/idea_users', {
      idea_user: params
  })
  end

  def get_contact(email)
    get("/idea_users?email=#{email}")
  end

  def get_portal_user(idea_portal_id, email)
    get("/idea_portals/#{idea_portal_id}/portal_users?email=#{email}")
  end

  def create_portal_user(idea_portal_id, params)
    post("/idea_portals/#{idea_portal_id}/portal_users", {
      portal_user: params
    })
  end

  def create_idea(product_id, params)
    post("/products/#{product_id}/ideas", {
      idea: params
    })
  end

  def create_comment(idea_id, params)
    post("/ideas/#{idea_id}/idea_comments", {
      idea_comment: params
    })
  end

  def create_idea_endorsement(idea_id, params)
    post("/ideas/#{idea_id}/endorsements", {
      idea_endorsement: params
    })
  end

  private
  def connection
    Faraday.new(url: @host) do |faraday|
      faraday.request :url_encoded
      faraday.response :raise_error
      faraday.headers['Authorization'] = "Bearer #{@api_key}"
    end
  end

  def get(route, url_params = {})
    # this operation will block until less than 290 shift calls have been made within the last minute
    @queue.shift

    begin
      response = @conn.get("/api/v1#{route}") do |req|
        req.params = url_params
        req.headers['Authorization'] = "Bearer #{@api_key}"
      end
    rescue Faraday::ClientError => e
      handle_error(e)
    else
      JSON.parse(response.body, symbolize_names: true)
    end
  end

  def post(route, body = nil)
    # this operation will block until less than 290 shift calls have been made within the last minute
    @queue.shift

    begin
      response = @conn.post("/api/v1#{route}") do |req|
        req.body = body
        req.headers['Authorization'] = "Bearer #{@api_key}"
      end
    rescue Faraday::BadRequestError => e
      response_body = JSON.parse(e.response[:body], symbolize_names: true)

      if response_body[:errors][:message] != 'Email A contact already exists with this email' &&
         response_body[:errors][:message] != 'Email A portal user already exists with this email'
        handle_error(e)
      end

      return 'already created'
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
    raise e
  end
end