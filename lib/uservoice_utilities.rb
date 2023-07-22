require 'csv'

module UserVoiceCsv
  #
  # Fetch all users with activity from UserVoice and write to CSV
  #
  def create_uv_users_csv(uv_api)
    columns = [
      {
        name: 'id',
        value: -> (item, _) { item[:id] }
      },
      {
        name: 'email',
        value: -> (item, _) { item[:email_address] }
      },
      {
        name: 'first_name',
        value: -> (item, _) { (item[:name] || '').split(' ')[0] }
      },
      {
        name: 'last_name',
        value: -> (item, _) { first_name, *last_name = (item[:name] || '').split(' '); last_name.join(' ') }
      },
      {
        name: 'sf_id',
        value: -> (item, included_items) { included_items[:crm_accounts][item[:links][:crm_account]] }
      }
    ]

    included_items = [
      {
        name: :crm_accounts,
        key: :id,
        value: :external_id
      }
    ]

    skip_user = -> (item) { item[:supported_suggestions_count] == 0 }

    create_uv_csv(uv_api, :users, columns, {skip_option: skip_user, included_items: included_items})
  end

  #
  # Fetch all suggestions from UserVoice and write to CSV
  #
  def create_uv_suggestions_csv(uv_api)
    columns = [
      {
        name: 'uv_id',
        value: -> (item, _) { item[:id] }
      },
      {
        name: 'title',
        value: -> (item, _) { item[:title] }
      },
      {
        name: 'body',
        value: -> (item, _) { item[:body] }
      },
      {
        name: 'created_at',
        value: -> (item, _) { item[:created_at] }
      },
      {
        name: 'updated_at',
        value: -> (item, _) { item[:updated_at] }
      },
      {
        name: 'state',
        value: -> (item, _) { item[:state] }
      },
      {
        name: 'created_by',
        value: -> (item, _) { item[:links][:created_by] }
      },
      {
        name: 'portal_url',
        value: -> (item, _) { item[:portal_url] }
      },
      {
        name: 'category',
        value: -> (item, included_items) { included_items[:categories][item[:links][:category]] }
      },
      {
        name: 'labels',
        value: -> (item, included_items) { (item[:links][:labels] || []).map { |label_id| included_items[:labels][label_id] }.join(',') }
      },
      {
        name: 'status',
        value: -> (item, included_items) { included_items[:statuses][item[:links][:status]] }
      }
    ]

    included_items = [
      {
        name: :categories,
        key: :id,
        value: :name
      },
      {
        name: :labels,
        key: :id,
        value: :name
      },
      {
        name: :statuses,
        key: :id,
        value: :name
      }
    ]

    create_uv_csv(uv_api, :suggestions, columns, {included_items: included_items})
  end

  #!
  #! PRIVATE FUNCTIONS
  #!
  private

  #
  # Create CSV of UV Data
  #
  def create_uv_csv(uv_api, object_name, columns, options = {})
    cursor = nil
    last_page = 0
    total_pages = 'unknown'
    cursor_file_path = "./tmp/#{object_name}_cursor.tmp"
    csv_file_path = "./tmp/all_#{object_name}.csv"

    csv = CSV.open(csv_file_path, 'a')

    # Check if we left off somewhere
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

  #
  # Clean up CSV
  #
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