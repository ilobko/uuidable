# frozen_string_literal: true

# Active Support 6.1 and 7.0 use Logger without requiring it.
require 'logger'
require 'active_record'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'uuidable'

require_relative 'support/models'

if ENV['UUIDABLE_DATABASE_URL']
  require_relative 'support/database'
else
  RSpec.configure { |config| config.filter_run_excluding :mysql }
end
