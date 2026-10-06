# frozen_string_literal: true

module Uuidable
  COLUMN_NAME = :uuid
  COLUMN_TYPE = :binary
  COLUMN_OPTIONS = { limit: 16, null: false }.freeze
  INDEX_OPTIONS = { unique: true }.freeze
  STORAGE_LIMITS = { binary: 16, text: 36 }.freeze

  class << self
    # Name of a new UUID column, given positionally or with the pre-1.0 `column_name:` option.
    def column_name(positional, keyword)
      if positional && keyword && positional.to_s != keyword.to_s
        raise ArgumentError, "UUID column named twice: #{positional.inspect} and column_name: #{keyword.inspect}"
      end

      positional || keyword || COLUMN_NAME
    end

    # Storage for new UUID columns that set neither `storage:` nor `limit:`.
    # Apps upgrading from 0.x can set :text so new columns match their 36-byte ones.
    def default_storage
      @default_storage || :binary
    end

    def default_storage=(storage)
      storage_limit(storage)
      @default_storage = storage
    end

    # Column options for a new UUID column, resolving `storage:` into a limit.
    def column_options(options)
      options = options.dup
      storage = options.delete(:storage)
      limit = storage_limit(storage || default_storage)
      if storage && options.key?(:limit) && options[:limit] != limit
        raise ArgumentError, "storage: #{storage.inspect} conflicts with limit: #{options[:limit].inspect}"
      end

      COLUMN_OPTIONS.merge(limit: limit).merge(options)
    end

    private

    def storage_limit(storage)
      STORAGE_LIMITS.fetch(storage) do
        raise ArgumentError, "UUID storage must be one of #{STORAGE_LIMITS.keys.inspect}, got #{storage.inspect}"
      end
    end
  end

  # Module adds method to table definition
  module TableDefinition
    def uuid(column_name = nil, **opts)
      index_opts = opts.delete(:index)
      index_opts = {} if index_opts.nil?

      column_name = Uuidable.column_name(column_name, opts.delete(:column_name))

      column column_name, COLUMN_TYPE, **Uuidable.column_options(opts)
      index column_name, **INDEX_OPTIONS.merge(index_opts) if index_opts
    end
  end

  # Module adds method to alter table migration
  module Migration
    def add_uuid_column(table_name, column_name = nil, **opts)
      index_opts = opts.delete(:index)
      index_opts = {} if index_opts == true

      column_name = Uuidable.column_name(column_name, opts.delete(:column_name))

      add_column table_name, column_name, COLUMN_TYPE, **Uuidable.column_options(opts)

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
