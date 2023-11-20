require 'csv'

module MigrationUtilities
  #
  # Fetch all organizations from Aha and write to CSV so we can
  # look up by Salesforce ID
  #
  def create_aha_organizations_csv(aha_api)
    csv = CSV.open('./tmp/organizations.csv', 'w')
    csv << ['sf_id', 'aha_org_id']

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
  def create_aha_contacts(aha_api, idea_portal_id)
    org_map = create_org_map
    total_users = File.read('./tmp/all_users.csv').each_line.count - 1


    # Check if we left off somewhere
    if !File.exists?('./tmp/created_users.csv')
      p "Created 0 of #{total_users} users..."
      CSV.open('./tmp/created_users.csv', 'w') do |csv|
        csv << ['uv_user_id', 'email', 'aha_contact_id', 'aha_portal_user_id', 'sf_org_id']
      end
    end

    created_users_email = CSV.read('./tmp/created_users.csv', headers: true).map { |row| row['email'] }
    created_users_csv = CSV.open('./tmp/created_users.csv', 'a')

    # Start parsing through users starting at the top
    CSV.read('./tmp/all_users.csv', headers: true).each_with_index do |row, index|
      email = row['email'].downcase
      next if created_users_email.include?(email)

      user_params = {
        email: email,
        first_name: row['first_name'],
        last_name: row['last_name'],
        idea_organization_id: org_map[row['sf_id']] ? org_map[row['sf_id']].to_i : nil,
        verified: true,
      }

      users_response = aha_api.create_contact(user_params)

      if users_response == 'already created'
        users_response = aha_api.get_contact(email)
        contact_id = users_response[:idea_users][0][:id]
      else
        contact_id = users_response[:idea_user][:id]
      end

      portal_user_response = aha_api.create_portal_user(idea_portal_id, user_params)

      if portal_user_response == 'already created'
        portal_user_response = aha_api.get_portal_user(idea_portal_id, email)
        portal_user_id = portal_user_response[:portal_users][0][:id]
      else
        portal_user_id = portal_user_response[:portal_user][:id]
      end

      created_users_email << email
      created_users_csv << [row['id'], email, contact_id, portal_user_id, row['sf_id']]

      p "Created #{index + 1} of #{total_users} users..." if (index + 1) % 20 == 0
    end

    created_users_csv.close

    p "Created #{total_users} users."
  end

  #
  # Create Aha Ideas
  #
  def create_aha_sf_ideas(aha_api, sf_api, product_id, options = {})
    status_map = options[:status_map]
    category_map = options[:category_map]
    default_status = options[:default_status]
    default_category = options[:default_category]
    fallback_user = options[:fallback_user]

    user_map = create_user_map
    total_ideas = File.read('./tmp/all_suggestions.csv').each_line.count - 1

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_ideas.csv')
      p "Created 0 of #{total_ideas} ideas..."
      CSV.open('./tmp/created_ideas.csv', 'w') do |csv|
        csv << ['uv_suggestion_id', 'aha_idea_id', 'sf_idea_id']
      end
    end

    created_ideas = CSV.read('./tmp/created_ideas.csv', headers: true).map { |row| row['uv_suggestion_id'] }
    created_ideas_csv = CSV.open('./tmp/created_ideas.csv', 'a')

    # Start parsing through suggestions starting at the top
    CSV.read('./tmp/all_suggestions.csv', headers: true).each_with_index do |row, index|
      next if created_ideas.include?(row['suggestion_id'])

      workflow_status = status_map && status_map[row['status']] ? status_map[row['status']] : default_status
      categories = category_map && category_map[row['category']] ? category_map[row['category']] : default_category
      created_by_email = user_map[row['created_by']] ? user_map[row['created_by']][:email] : fallback_user[:email]
      body = row['body'] ? row['body'].gsub("\n", "</p><p>") : ''

      body = '<p>' + body + '</p>'

      # Create the idea in Aha
      aha_idea_params = {
        name: row['title'],
        description: body,
        workflow_status: workflow_status,
        categories: categories,
        created_by: created_by_email,
        created_at: row['created_at'],
        visibility: 'public',
      }

      aha_response = aha_api.create_idea(product_id, aha_idea_params)
      idea_id = aha_response[:idea][:id]

      endorsement_params = {
        email: created_by_email,
        created_at: row['created_at']
      }

      aha_api.create_idea_endorsement(idea_id, endorsement_params)
      sf_user_id = sf_api.fetch_user_id(created_by_email)

      # Create the idea in SF
      sf_idea_params = {
        Name: row['title'][0..79],
        ahaapp__ReferenceNum__c: aha_response[:idea][:reference_num],
        ahaapp__Status__c: aha_response[:idea][:workflow_status][:name],
        CreatedById: sf_user_id || fallback_user[:sf_user_id],
      }

      sf_response = sf_api.create_idea(sf_idea_params)

      created_ideas << row['suggestion_id']
      created_ideas_csv << [row['suggestion_id'], idea_id, sf_response[:id]]

      p "Created #{index + 1} of #{total_ideas} ideas..." if (index + 1) % 20 == 0
    end

    created_ideas_csv.close

    p "Created #{total_ideas} ideas."
  end

  #
  # Create comments on Aha Ideas
  #
  def create_aha_comments(aha_api, fallback_user)
    user_map = create_user_map
    idea_map = create_idea_map
    total_comments = File.read('./tmp/all_comments.csv').each_line.count - 1

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_comments.csv')
      p "Created 0 of #{total_comments} comments..."
      CSV.open('./tmp/created_comments.csv', 'w') do |csv|
        csv << ['uv_comment_id', 'aha_comment_id']
      end
    end

    created_comments = CSV.read('./tmp/created_comments.csv', headers: true).map { |row| row['uv_comment_id'] }
    created_comments_csv = CSV.open('./tmp/created_comments.csv', 'a')

    # Start parsing through comments starting at the top
    CSV.read('./tmp/all_comments.csv', headers: true).each_with_index do |row, index|
      next if created_comments.include?(row['comment_id']) || !idea_map[row['suggestion_id']]

      created_by = user_map[row['created_by']] ? user_map[row['created_by']][:aha_portal_user_id] : fallback_user[:portal_user_id]

      comment_params = {
        idea_id: idea_map[row['suggestion_id']][:aha_idea_id],
        portal_user: {
          id: created_by,
        },
        visibility: row['is_admin_comment'] == 'true' ? 'employee_or_creator' : 'public',
        body: row['body'],
        created_at: row['created_at']
      }

      response = aha_api.create_comment(idea_map[row['suggestion_id']][:aha_idea_id], comment_params)
      comment_id = response[:idea_comment][:id]

      created_comments << row['comment_id']
      created_comments_csv << [row['comment_id'], comment_id]

      p "Created #{index + 1} of #{total_comments} comments..." if (index + 1) % 20 == 0
    end

    created_comments_csv.close
    p "Created #{total_comments} comments."
  end

  #
  # Create supporters/endorsements (votes) on Aha Ideas
  #
  def create_aha_endorsements(aha_api, fallback_user, idea_portal_id)
    user_map = create_user_map
    idea_map = create_idea_map
    total_endorsements = File.read('./tmp/all_supporters.csv').each_line.count - 1

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_endorsements.csv')
      p "Created 0 of #{total_endorsements} endorsements..."
      CSV.open('./tmp/created_endorsements.csv', 'w') do |csv|
        csv << ['uv_supporter_id', 'aha_endorsement_id']
      end
    end

    created_endorsements = CSV.read('./tmp/created_endorsements.csv', headers: true).map { |row| row['uv_supporter_id'] }
    created_endorsements_csv = CSV.open('./tmp/created_endorsements.csv', 'a')

    # Start parsing through supporters starting at the top
    CSV.read('./tmp/all_supporters.csv', headers: true).each_with_index do |row, index|
      next if created_endorsements.include?(row['supporter_id']) || !idea_map[row['suggestion_id']]

      created_by = user_map[row['created_by']] ? user_map[row['created_by']][:email] : fallback_user[:email]

      endorsement_params = {
        email: created_by,
        created_at: row['created_at']
      }

      response = aha_api.create_idea_endorsement(idea_map[row['suggestion_id']][:aha_idea_id], endorsement_params)

      idea_endorsement_id = response == 'already created' ? nil : response[:idea_endorsement][:id]

      if idea_endorsement_id && row['is_subscribed'] == 'true' && created_by != fallback_user[:email]
        subscription_params = {
          email: created_by,
          idea_portal_id: idea_portal_id
        }
        aha_api.create_idea_subscription(idea_map[row['suggestion_id']][:aha_idea_id], endorsement_params)
      end

      created_endorsements << row['supporter_id']
      created_endorsements_csv << [row['supporter_id'], idea_endorsement_id]
      p "Created #{index + 1} of #{total_endorsements} endorsements..." if (index + 1) % 20 == 0
    end

    created_endorsements_csv.close
    p "Created #{total_endorsements} endorsements."
  end

  #
  # Create feedback records/endorsements (proxy votes) on Aha Ideas
  #
  def create_aha_sf_proxy_endorsements(aha_api, sf_api, fallback_user, sf_subdomain)
    user_map = create_user_map
    org_map = create_org_map
    idea_map = create_idea_map
    total_endorsements = File.read('./tmp/all_feedback_records.csv').each_line.count - 1

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_proxy_endorsements.csv')
      p "Created 0 of #{total_endorsements} proxy endorsements..."
      CSV.open('./tmp/created_proxy_endorsements.csv', 'w') do |csv|
        csv << ['uv_feedback_record_id', 'aha_endorsement_id']
      end
    end

    created_proxy_endorsements = CSV.read('./tmp/created_proxy_endorsements.csv', headers: true).map { |row| row['uv_feedback_record_id'] }
    created_proxy_endorsements_csv = CSV.open('./tmp/created_proxy_endorsements.csv', 'a')

    # Start parsing through feedback records starting at the top
    CSV.read('./tmp/all_feedback_records.csv', headers: true).each_with_index do |row, index|
      next if created_proxy_endorsements.include?(row['feedback_record_id'])
      next if !org_map[row['sf_id']]
      next if !idea_map[row['suggestion_id']]

      created_by = user_map[row['created_by']] ? user_map[row['created_by']][:email] : fallback_user[:email]

      # Create the endorsement in Aha
      endorsement_params = {
        email: created_by,
        idea_organization_id: org_map[row['sf_id']].to_i,
        link: row['sf_url'],
        description: row['body'],
        contacts: user_map[row['user_id']][:email],
        created_at: row['created_at']
      }

      response = aha_api.create_idea_endorsement(idea_map[row['suggestion_id']][:aha_idea_id], endorsement_params)
      idea_endorsement_id = response[:idea_endorsement][:id]

      if idea_endorsement_id
        sf_user_id = sf_api.fetch_user_id(user_map[row['user_id']][:email])

        # Check that SF doesn't already contain a link between the Idea and an Account
        if !sf_api.fetch_aha_link(idea_map[row['suggestion_id']][:sf_idea_id], row['sf_id'])
          # Create the Ideas/SF Account link
          sf_link_params = {
            ahaapp__LinkedBy__c: sf_user_id || fallback_user[:sf_user_id],
            ahaapp__AhaIdea__c: idea_map[row['suggestion_id']][:sf_idea_id],
            ahaapp__Account__c: row['sf_id']
          }

          sf_api.create_aha_idea_link(sf_link_params)
        end

        sf_account_name = sf_api.fetch_org_name(row['sf_id'])

        # Link the Aha endorsement to a Salesforce record
        aha_integration_params = [
          {name: 'account_id', value: row['sf_id']},
          {name: 'related_id', value: row['sf_id']},
          {name: 'related_type', value: 'Account'},
          {name: 'account_name', value: sf_account_name},
          {name: 'base_url', value: "https://#{sf_subdomain}.my.salesforce.com"},
        ]

        aha_api.create_endorsement_integration_fields(idea_endorsement_id, aha_integration_params)
      end

      created_proxy_endorsements << row['feedback_record_id']
      created_proxy_endorsements_csv << [row['feedback_record_id'], idea_endorsement_id]
      p "Created #{index + 1} of #{total_endorsements} proxy endorsements..." if (index + 1) % 20 == 0
    end

    created_proxy_endorsements_csv.close
    p "Created #{total_endorsements} proxy endorsements."
  end

  def merge_aha_ideas(aha_api)
    idea_map = create_idea_map

    # Start parsing through suggestions starting at the top
    CSV.read('./tmp/all_suggestions.csv', headers: true).each_with_index do |row, index|
      next if !row['parent_suggestion'] || !idea_map[row['suggestion_id']]

      aha_idea_id = idea_map[row['suggestion_id']][:aha_idea_id]

      # Merge the idea in Aha
      aha_idea_params = {
        duplicate_idea: idea_map[row['parent_suggestion']][:aha_idea_id]
      }

      aha_response = aha_api.update_idea(aha_idea_id, aha_idea_params)
    end
  end

  #!
  #! PRIVATE FUNCTIONS
  #!
  private

  #
  # Create map of UV user id -> user details
  #
  def create_user_map
    user_map = {}
    user_csv = CSV.read('./tmp/created_users.csv', headers: true)
    user_csv.each do |row|
      user_map[row['uv_user_id']] = {
        aha_contact_id: row['aha_contact_id'],
        aha_portal_user_id: row['aha_portal_user_id'],
        email: row['email'],
        sf_org_id: row['sf_org_id'],
      }
    end
    user_map
  end

  #
  # Create map of sf_id -> Aha org id
  #
  def create_org_map
    org_map = {}
    org_csv = CSV.read('./tmp/organizations.csv', headers: true)
    org_csv.each do |row|
      next if row['sf_id'] == ''
      org_map[row['sf_id']] = row['aha_org_id']
    end
    org_map
  end

  #
  # Create map of UV suggestion id -> Aha idea id
  #
  def create_idea_map
    idea_map = {}
    idea_csv = CSV.read('./tmp/created_ideas.csv', headers: true)
    idea_csv.each do |row|
      idea_map[row['uv_suggestion_id']] = {
        aha_idea_id: row['aha_idea_id'],
        sf_idea_id: row['sf_idea_id'],
      }
    end
    idea_map
  end
end