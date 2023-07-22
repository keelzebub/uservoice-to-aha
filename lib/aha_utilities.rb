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
        csv << ['uv_id', 'email', 'aha_contact_id', 'aha_portal_user_id']
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
end