require 'csv'

module AhaUtilities
  #
  # Fetch all organizations from Aha and write to CSV so we can
  # look up by Salesforce ID
  #
  def create_aha_organizations_csv(aha_api)
    csv = CSV.open('./tmp/organizations.csv', 'w')
    csv << ['sf_id', 'uv_org_id']

    current_page = 1
    total_pages = 1
    while current_page <= total_pages
      org_response = aha_api.fetch_organizations(current_page)
      total_pages = org_response[:pagination][:total_pages]
      p "Fetching organizations (#{current_page} of #{total_pages})..."

      current_page += 1
      org_response[:idea_organizations].each do |org|
        sf_custom_field = org[:custom_fields].find { |field| field[:key] == 'salesforce_id' }
        sf_id = sf_custom_field.nil? ? '' : sf_custom_field[:value]
        csv << [sf_id, org[:id]]
      end
    end

    File.open('./tmp/org_fetch_status.tmp', 'w') { |f| f.write 'complete' }
  end

  #
  # Create Aha Users
  #
  def create_aha_users(aha_api, idea_portal_id)
    # Create map of sf_id -> Aha org id
    aha_org_id = {}
    org_csv = CSV.read('./tmp/organizations.csv', headers: true)
    org_csv.read.each do |row|
      next if row['sf_id'] == ''
      aha_org_id[row['sf_id']] = row['uv_org_id']
    end

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_users.csv')
      CSV.open('./tmp/created_users.csv', 'w') do |csv|
        csv << ['uv_user_id', 'email', 'aha_contact_id', 'aha_portal_user_id']
      end
    end

    created_users_email = CSV.read('./tmp/created_users.csv', headers: true).map { |row| row['email'] }
    created_users_csv = CSV.open('./tmp/created_users.csv', 'a')

    # Start parsing through users starting at the top
    CSV.read('./tmp/all_users.csv', headers: true).each_with_index do |row, index|
      next if created_users_email.include?(row['email'])

      user_params = {
        email: row['email'],
        first_name: row['first_name'],
        last_name: row['last_name'],
        idea_organization_id: aha_org_id[row['sf_id']] ? aha_org_id[row['sf_id']].to_i : nil,
        verified: true,
      }

      begin
        users_response = aha_api.create_contact(user_params)
        contact_id = users_response[:idea_user][:id]
      rescue Faraday::BadRequestError => e
        response_body = JSON.parse(e.response[:body], symbolize_names: true)
        if response_body[:errors][:message] != 'Email A contact already exists with this email'
          raise e
        end

        contact_id = nil
      end

      portal_user_response = aha_api.create_portal_user(idea_portal_id, user_params)
      portal_user_id = portal_user_response[:portal_user][:id]

      created_users_email << row['email']
      created_users_csv << [row['id'], row['email'], contact_id, portal_user_id]

      break
    end
  end

  #
  # Create Aha Ideas
  #
  def create_aha_ideas(aha_api, product_id)
    # Create map of UV user id -> Aha portal user id
    user_map = {}
    user_csv = CSV.read('./tmp/created_users.csv', headers: true)
    user_csv.read.each do |row|
      user_map[row['uv_user_id']] = row['email']
    end

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_ideas.csv')
      CSV.open('./tmp/created_ideas.csv', 'w') do |csv|
        csv << ['uv_suggestion_id', 'aha_idea_id']
      end
    end

    created_suggestions = CSV.read('./tmp/created_suggestions.csv', headers: true).map { |row| row['uv_suggestion_id'] }
    created_suggestions_csv = CSV.open('./tmp/created_suggestions.csv', 'a')

    # Start parsing through suggestions starting at the top
    CSV.read('./tmp/all_suggestions.csv', headers: true).each_with_index do |row, index|
      next if created_suggestions.include?(row['suggestion_id'])

      # TODO: figure out status and category mapping
      # workflow_status = 'pending'
      # categories = 'Classy'

      idea_params = {
        name: row['title'],
        description: row['title'],
        workflow_status: workflow_status,
        categories: categories,
        created_by: user_map[row['created_by']],
        created_at: row['created_at']
        visibility: 'public',
      }

      response = aha_api.create_idea(idea_params)
      idea_id = response[:idea][:id]

      created_suggestions << row['suggestion_id']
      created_suggestions_csv << [row['suggestion_id'], idea_id]
    end
  end

  #
  # Create supporters/endorsements (votes) on Aha Ideas
  #
  def create_aha_endorsements
    # Create map of UV user id -> Aha portal user id
    user_map = {}
    user_csv = CSV.read('./tmp/created_users.csv', headers: true)
    user_csv.read.each do |row|
      user_map[row['uv_user_id']] = row['email']
    end

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_supporters.csv')
      CSV.open('./tmp/created_supporters.csv', 'w') do |csv|
        csv << ['uv_supporter_id', 'aha_endorsement_id']
      end
    end

    created_supporters = CSV.read('./tmp/created_supporters.csv', headers: true).map { |row| row['uv_supporter_id'] }
    created_supporters_csv = CSV.open('./tmp/created_supporters.csv', 'a')

    # Start parsing through supporters starting at the top
    CSV.read('./tmp/all_suggestions.csv', headers: true).each_with_index do |row, index|
      next if created_supporters.include?(row['supporter_id'])

      # weight = 1
      # weight = 2 if row['importance_score'] == 'Important'
      # weight = 3 if row['importance_score'] == 'Critical'

      endorsement_params = {
        email: user_map[row['created_by']],
        # weight: weight,
      }

      response = aha_api.create_endorsement(row['suggestion_id'], endorsement_params)
      idea_endorsement_id = response[:idea_endorsement][:id]

      created_supporters << row['supporter_id']
      created_supporters_csv << [row['supporter_id'], idea_endorsement]
    end
  end
end