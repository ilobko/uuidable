# frozen_string_literal: true

require 'uuidable/v1_conversion'

module Uuidable
  # Migration helpers that convert pre-v1 36-byte UUID columns to 16 bytes. Needs MySQL 8.
  # Converting and rolling back are each other's inverse, so either works inside `change`.
  module V1MigrationHelpers
    NEW_POSTFIX = '__new'
    OLD_POSTFIX = '__old'

    # Converts UUID columns to 16 bytes and keeps the original values in *__old columns.
    # @param columns_options [Hash{String, Symbol => Hash}] columns to convert, with :null or :comment overrides
    # @param opts [Hash] :limit and :skip_type_check for selecting columns, see #valid_column_for_migration?
    def uuidable_migrate_uuid_columns_to_v1(table_name, columns_options = {}, **opts)
      columns_options = columns_options.transform_keys(&:to_s)
      reversible do |direction|
        direction.up { uuidable_convert_to_v1(table_name, columns_options, opts) }
        direction.down { uuidable_restore_from_v1(table_name, columns_options.keys) }
      end
    end

    # Restores the original values from *__old columns. Refuses to run if rows changed
    # without the V1ModelMigration callbacks, because the old columns would not have them.
    def uuidable_rollback_uuid_columns_from_v1(table_name, *columns)
      columns = columns.map(&:to_s)
      reversible do |direction|
        direction.up { uuidable_restore_from_v1(table_name, columns) }
        direction.down { uuidable_convert_to_v1(table_name, columns.to_h { |name| [name, {}] }, {}) }
      end
    end

    def uuidable_migrate_all_pre_v1_uuid_columns!
      tables.each do |table_name|
        uuidable_migrate_uuid_columns_to_v1 table_name
      end
    end

    def uuidable_rollback_all_pre_v1_uuid_columns!
      tables.each do |table_name|
        uuidable_rollback_uuid_columns_from_v1 table_name
      end
    end

    # WARNING: this is irreversible migration! It will drop all *uuid__old columns and their indexes in all tables!
    def uuidable_drop_all_pre_v1_uuid_columns!
      tables.each do |table_name|
        indexes = indexes(table_name)
        change_table table_name, bulk: true do |t|
          connection.columns(table_name).each do |column|
            next unless column.name.include?('uuid') && column.name.end_with?(OLD_POSTFIX)

            indexes.each do |ind|
              next unless ind.columns.include?(column.name)

              t.remove_index name: ind.name
            end

            t.remove column.name
          end
        end
      end
    end

    def valid_column_for_migration?(column, limit: 36, skip_type_check: false)
      column.name.include?('uuid') &&
        !column.name.include?(NEW_POSTFIX) &&
        !column.name.include?(OLD_POSTFIX) &&
        (skip_type_check || (column.type == :binary && column.limit == limit))
    end

    def indexes_with_columns(table_name, columns)
      indexes(table_name).select { |ind| (ind.columns & columns.map(&:name)).any? }
    end

    private

    def uuidable_convert_to_v1(table_name, columns_options, opts)
      columns = connection.columns(table_name).select do |column|
        (columns_options.empty? || columns_options.key?(column.name)) && valid_column_for_migration?(column, **opts)
      end
      V1Conversion.new(connection, table_name).migrate(columns, columns_options)
    end

    def uuidable_restore_from_v1(table_name, names)
      all_columns = connection.columns(table_name)
      old_names = all_columns.map(&:name).select { |name| name.end_with?(OLD_POSTFIX) }
      columns = all_columns.select do |column|
        (names.empty? || names.include?(column.name)) && valid_column_for_migration?(column, limit: 16) &&
          old_names.include?("#{column.name}#{OLD_POSTFIX}")
      end
      V1Conversion.new(connection, table_name).rollback(columns)
    end
  end
end
