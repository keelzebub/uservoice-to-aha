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

    File.open('./tmp/org_fetch_status.tmp', 'w') { |f| f.write 'complete' }
  end

  def create_uv_csv(uv_api, object_name, columns, options = {})
    cursor = nil
    last_page = 0
    total_pages = 'unknown'
    cursor_file_path = "./tmp/#{object_name}_cursor.tmp"
    csv_file_path = "./tmp/all_#{object_name}.csv"

    csv = CSV.open(csv_file_path, 'a')

    # Check if we left off somewhere (contact lists are long)
    if File.exists?(cursor_file_path)
      p "Picking up UserVoice #{object_name} fetch from where we left off"
      cursor, last_page = File.open(cursor_file_path).read.split(',')
      last_page = last_page.to_i
      remove_last_page_from_csv(csv_file_path, cursor)
    else
      p "Starting UserVoice #{object_name} fetch from the beginning"
      csv << columns.map { |col| col[:name] } + ['cursor']
    end

    loop do
      p '-'*40
      p "Fetching UserVoice #{object_name} (#{last_page + 1} of #{total_pages})..."
      p cursor

      response = uv_api.send("fetch_#{object_name}", cursor)
      items = response[object_name]

      included_item_map = {}

      (options[:included_items] || []).each do |included_item|
        included_name = included_item[:name]
        included_key = included_item[:key]
        included_value = included_item[:value]

        included_item_map[included_name] = {}

        (response[included_name] || []).each do |item|
          included_item_map[included_name][item[included_key]] = item[included_value]
        end
      end

      items.each do |item|
        next if options[:skip_option] && options[:skip_option].call(item) # here <<<<<<

        row = columns.map { |col| col[:value].call(item, included_item_map) }

        first_name, *last_name = (item[:name] || '').split(' ')
        last_name = last_name.join(' ')

        csv << row + [cursor]
      end

      break if response[:pagination][:cursor].nil?
      total_pages = response[:pagination][:total_pages]
      cursor = response[:pagination][:cursor]
      last_page += 1
      File.open(cursor_file_path, 'w') { |f| f.write "#{cursor},#{last_page}" }
    end
  end

  def create_aha_contacts(aha_api, idea_portal_id)
    # Create map of sf_id -> Aha org id
    aha_org_id = {}
    org_csv = CSV.open('./tmp/organizations.csv', 'r')
    org_csv.read.each do |row|
      next if row[0] == ''
      aha_org_id[row[0]] = row[1]
    end

    created_contacts_email = CSV.read('./tmp/created_contacts.csv').map { |row| row[0] }
    created_contacts_csv = CSV.open('./tmp/created_contacts.csv', 'a')

    # Start parsing through contacts starting at the top
    CSV.read('./tmp/all_contacts.csv', headers: true).each_with_index do |row, index|
      next if created_contacts_email.include?(row[0])

      user_params = {
        email: row[0],
        first_name: row[1],
        last_name: row[2],
        idea_organization_id: aha_org_id[row[3]] ? aha_org_id[row[3]].to_i : nil,
        verified: true,
      }

      begin
        contacts_response = aha_api.create_contact(user_params)
        contact_id = contacts_response[:idea_user][:id]
      rescue Faraday::BadRequestError => e
        response_body = JSON.parse(e.response[:body], symbolize_names: true)
        if response_body[:errors][:message] != 'Email A contact already exists with this email'
          raise e
        end

        contact_id = nil
      end

      portal_user_response = aha_api.create_portal_user(idea_portal_id, user_params)
      portal_user_id = portal_user_response[:portal_user][:id]

      created_contacts_email << row[0]
      created_contacts_csv << [row[0], contact_id, portal_user_id]

      ap user_params
      break
    end
  end

  private

  def remove_last_page_from_csv(csv_file, cursor)
    table = CSV.table(csv_file)

    table.delete_if do |row|
      row[:cursor] == cursor
    end

    File.open(csv_file, 'w') do |f|
      f.write(table.to_csv)
    end
  end
end