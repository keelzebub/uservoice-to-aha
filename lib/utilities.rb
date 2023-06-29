require 'csv'

module Utilities
  def create_aha_organizations_csv(aha_api)
    p 'Fetching organizations from Aha'
    # Fetch all organizations from Aha and write to CSV so we can look up by Salesforce ID
    csv = CSV.open('./tmp/organizations.csv', 'w')

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

    File.open('./tmp/progress.tmp', 'w') { |f| f.write 'org_fetch_complete' }
  end

  def create_uv_contacts_csv(uv_api)
    contacts_cursor = nil
    last_page = 0
    total_pages = 'unknown'

    csv = CSV.open('./tmp/contacts.csv', 'a')

    # Check if we left off somewhere (contact lists are long)
    if File.exists?('./tmp/contacts_cursor.tmp')
      p "Picking up UserVoice contact fetch from where we left off"
      contacts_cursor, last_page = File.open('./tmp/contacts_cursor.tmp').read.split(',')
      last_page = last_page.to_i
      remove_incomplete_page_from_csv('./tmp/contacts.csv', contacts_cursor)
    else
      p 'Starting UserVoice contact fetch from the beginning'

      csv << [ 'email', 'first_name', 'last_name', 'sf_id', 'contacts_cursor' ]
    end


    loop do
      p '-'*40
      p "Fetching UserVoice contacts (#{last_page + 1} of #{total_pages})..."
      p contacts_cursor

      users_response = uv_api.fetch_users(contacts_cursor)
      users = users_response[:users]
      crm_accounts = {}

      (users_response[:crm_accounts] || []).each do |account|
        crm_accounts[account[:id]] = account[:external_id]
      end

      users.each do |user|
        next if user[:supported_suggestions_count] == 0

        first_name, *last_name = (user[:name] || '').split(' ')
        last_name = last_name.join(' ')

        # email, first_name, last_name, sf_account_id, cursor
        csv << [
          user[:email_address],
          first_name,
          last_name,
          crm_accounts[user[:links][:crm_account]],
          contacts_cursor
        ]
      end

      break if users_response[:pagination][:cursor].nil?
      total_pages = users_response[:pagination][:total_pages]
      contacts_cursor = users_response[:pagination][:cursor]
      last_page += 1
      File.open('./tmp/contacts_cursor.tmp', 'w') { |f| f.write "#{contacts_cursor},#{last_page}" }
    end

    File.open('./tmp/progress.tmp', 'w') { |f| f.write 'contact_fetch_complete' }
  end

  def create_aha_idea_users
  end

  private

  def remove_incomplete_page_from_csv(csv_file, contacts_cursor)
    table = CSV.table(csv_file)

    table.delete_if do |row|
      row[4] == contacts_cursor
    end

    File.open(csv_file, 'w') do |f|
      f.write(table.to_csv)
    end
  end
end