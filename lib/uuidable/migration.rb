# frozen_string_literal: true

module Uuidable
  COLUMN_NAME = :uuid
  COLUMN_TYPE = :binary
  COLUMN_OPTIONS = { limit: 16, null: false }.freeze
  INDEX_OPTIONS = { unique: true }.freeze

  class << self
    # Name of a new UUID column, given positionally or with the pre-1.0 `column_name:` option.
    def column_name(positional, keyword)
      if positional && keyword && positional.to_s != keyword.to_s
        raise ArgumentError, "UUID column named twice: #{positional.inspect} and column_name: #{keyword.inspect}"
      end

      positional || keyword || COLUMN_NAME
    end
  end

  # Module adds method to table definition
  module TableDefinition
    def uuid(column_name = nil, **opts)
      index_opts = opts.delete(:index)
      index_opts = {} if index_opts.nil?

      column_name = Uuidable.column_name(column_name, opts.delete(:column_name))

      column column_name, COLUMN_TYPE, **COLUMN_OPTIONS.merge(opts)
      index column_name, **INDEX_OPTIONS.merge(index_opts) if index_opts
    end
  end

  # Module adds method to alter table migration
  module Migration
    def add_uuid_column(table_name, column_name = nil, **opts)
      index_opts = opts.delete(:index)
      index_opts = {} if index_opts == true

      column_name = Uuidable.column_name(column_name, opts.delete(:column_name))

      add_column table_name, column_name, COLUMN_TYPE, **COLUMN_OPTIONS.merge(opts)

      add_uuid_index(table_name, index_opts.merge(column_name: column_name)) if index_opts
    end

    def add_uuid_index(table_name, opts = {})
      column_name = opts.delete(:column_name) || COLUMN_NAME

      add_index table_name, column_name, **INDEX_OPTIONS.merge(opts)
    end
  end
end

if defined? ActiveRecord::ConnectionAdapters::TableDefinition
  ActiveRecord::ConnectionAdapters::TableDefinition.include Uuidable::TableDefinition
end

ActiveRecord::Migration.include Uuidable::Migration if defined? ActiveRecord::Migration
