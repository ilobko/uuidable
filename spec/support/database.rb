# frozen_string_literal: true

require 'uri'

database_url = ENV.fetch('UUIDABLE_DATABASE_URL')
unless URI.parse(database_url).path.end_with?('_test')
  raise 'UUIDABLE_DATABASE_URL must point to a dedicated database whose name ends in _test'
end

ActiveRecord::Base.establish_connection(database_url)
ActiveRecord::Migration.verbose = false
