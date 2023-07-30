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
  def create_aha_contacts(aha_api, idea_portal_id)
    org_map = create_org_map

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
        idea_organization_id: org_map[row['sf_id']] ? org_map[row['sf_id']].to_i : nil,
        verified: true,
      }

      users_response = aha_api.create_contact(user_params)

      if users_response == 'already created'
        users_response = aha_api.get_contact(row['email'])
        contact_id = users_response[:idea_users][0][:id]
      else
        contact_id = users_response[:idea_user][:id]
      end

      portal_user_response = aha_api.create_portal_user(idea_portal_id, user_params)

      if portal_user_response == 'already created'
        portal_user_response = aha_api.get_portal_user(idea_portal_id, row['email'])
        portal_user_id = portal_user_response[:portal_users][0][:id]
      else
        portal_user_id = portal_user_response[:portal_user][:id]
      end

      created_users_email << row['email']
      created_users_csv << [row['id'], row['email'], contact_id, portal_user_id]
    end

    created_users_csv.close
  end

  #
  # Create Aha Ideas
  #
  def create_aha_ideas(aha_api, product_id)
    user_map = create_user_email_map

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_suggestions.csv')
      CSV.open('./tmp/created_suggestions.csv', 'w') do |csv|
        csv << ['uv_suggestion_id', 'aha_idea_id']
      end
    end

    created_suggestions = CSV.read('./tmp/created_suggestions.csv', headers: true).map { |row| row['uv_suggestion_id'] }
    created_suggestions_csv = CSV.open('./tmp/created_suggestions.csv', 'a')

    # Start parsing through suggestions starting at the top
    CSV.read('./tmp/all_suggestions.csv', headers: true).each_with_index do |row, index|
      next if created_suggestions.include?(row['suggestion_id'])

      # TODO: figure out status and category mapping
      workflow_status = 'New'
      categories = 'Classy'

      idea_params = {
        name: row['title'],
        description: row['body'],
        workflow_status: workflow_status,
        categories: categories,
        created_by: user_map[row['created_by']],
        created_at: row['created_at'],
        visibility: 'public',
      }

      response = aha_api.create_idea(product_id, idea_params)
      idea_id = response[:idea][:id]

      endorsement_params = {
        email: user_map[row['created_by']],
        created_at: row['created_at']
      }

      aha_api.create_idea_endorsement(idea_id, endorsement_params)

      created_suggestions << row['suggestion_id']
      created_suggestions_csv << [row['suggestion_id'], idea_id]
    end

    created_suggestions_csv.close
  end

  #
  # Create comments on Aha Ideas
  #
  def create_aha_comments(aha_api)
    user_map = create_user_portal_id_map
    idea_map = create_idea_map

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_comments.csv')
      CSV.open('./tmp/created_comments.csv', 'w') do |csv|
        csv << ['uv_comment_id', 'aha_comment_id']
      end
    end

    created_comments = CSV.read('./tmp/created_comments.csv', headers: true).map { |row| row['uv_comment_id'] }
    created_comments_csv = CSV.open('./tmp/created_comments.csv', 'a')

    # Start parsing through comments starting at the top
    CSV.read('./tmp/all_comments.csv', headers: true).each_with_index do |row, index|
      next if created_comments.include?(row['comment_id'])

      comment_params = {
        idea_id: idea_map[row['suggestion_id']],
        portal_user: {
          id: user_map[row['created_by']],
        },
        body: row['body'],
        created_at: row['created_at']
      }

      response = aha_api.create_comment(idea_map[row['suggestion_id']], comment_params)
      comment_id = response[:idea_comment][:id]

      created_comments << row['comment_id']
      created_comments_csv << [row['comment_id'], comment_id]
    end

    created_comments_csv.close
  end

  #
  # Create supporters/endorsements (votes) on Aha Ideas
  #
  def create_aha_endorsements(aha_api)
    user_map = create_user_email_map
    idea_map = create_idea_map

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_supporters.csv')
      CSV.open('./tmp/created_supporters.csv', 'w') do |csv|
        csv << ['uv_supporter_id', 'aha_endorsement_id']
      end
    end

    created_supporters = CSV.read('./tmp/created_supporters.csv', headers: true).map { |row| row['uv_supporter_id'] }
    created_supporters_csv = CSV.open('./tmp/created_supporters.csv', 'a')

    # Start parsing through supporters starting at the top
    CSV.read('./tmp/all_supporters.csv', headers: true).each_with_index do |row, index|
      next if created_supporters.include?(row['supporter_id'])

      # weight = 1
      # weight = 2 if row['importance_score'] == 'Important'
      # weight = 3 if row['importance_score'] == 'Critical'

      endorsement_params = {
        email: user_map[row['created_by']],
        created_at: row['created_at']
        # weight: weight,
      }

      response = aha_api.create_idea_endorsement(idea_map[row['suggestion_id']], endorsement_params)
      idea_endorsement_id = response[:idea_endorsement][:id]

      created_supporters << row['supporter_id']
      created_supporters_csv << [row['supporter_id'], idea_endorsement_id]
    end

    created_supporters_csv.close
  end

  #
  # Create feedback records/endorsements (proxy votes) on Aha Ideas
  #
  def create_aha_proxy_endorsements(aha_api)
    user_map = create_user_email_map
    org_map = create_org_map
    idea_map = create_idea_map

    # Check if we left off somewhere
    if !File.exists?('./tmp/created_feedback_records.csv')
      CSV.open('./tmp/created_feedback_records.csv', 'w') do |csv|
        csv << ['uv_feedback_record_id', 'aha_endorsement_id']
      end
    end

    created_feedback_records = CSV.read('./tmp/created_feedback_records.csv', headers: true).map { |row| row['uv_feedback_record_id'] }
    created_feedback_records_csv = CSV.open('./tmp/created_feedback_records.csv', 'a')

    # Start parsing through feedback records starting at the top
    CSV.read('./tmp/all_feedback_records.csv', headers: true).each_with_index do |row, index|
      next if created_feedback_records.include?(row['feedback_record_id'])
      next if !org_map[row['sf_id']]

      endorsement_params = {
        email: user_map[row['created_by']],
        idea_organization_id: org_map[row['sf_id']].to_i,
        link: row['sf_url'],
        description: row['body'],
        contacts: user_map[row['user_id']],
        created_at: row['created_at']
      }

      response = aha_api.create_idea_endorsement(idea_map[row['suggestion_id']], endorsement_params)
      idea_endorsement_id = response[:idea_endorsement][:id]

      created_feedback_records << row['feedback_record_id']
      created_feedback_records_csv << [row['feedback_record_id'], idea_endorsement_id]
    end

    created_feedback_records_csv.close
  end

  #!
  #! PRIVATE FUNCTIONS
  #!
  private

  #
  # Create map of UV user id -> email
  #
  def create_user_email_map
    user_map = {}
    user_csv = CSV.read('./tmp/created_users.csv', headers: true)
    user_csv.each do |row|
      user_map[row['uv_user_id']] = row['email']
    end
    user_map
  end

  #
  # Create map of UV user id -> Aha portal user id
  #
  def create_user_portal_id_map
    user_map = {}
    user_csv = CSV.read('./tmp/created_users.csv', headers: true)
    user_csv.each do |row|
      user_map[row['uv_user_id']] = row['aha_portal_user_id']
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
      org_map[row['sf_id']] = row['uv_org_id']
    end
    org_map
  end

  #
  # Create map of UV suggestion id -> Aha idea id
  #
  def create_idea_map
    idea_map = {}
    idea_csv = CSV.read('./tmp/created_suggestions.csv', headers: true)
    idea_csv.each do |row|
      idea_map[row['uv_suggestion_id']] = row['aha_idea_id']
    end
    idea_map
  end
end