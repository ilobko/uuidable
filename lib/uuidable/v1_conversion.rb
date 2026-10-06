# frozen_string_literal: true

module Uuidable
  # Converts UUID columns from the pre-v1 36-byte text form to 16 bytes and back,
  # keeping the text in *__old columns between the two. Needs MySQL 8.
  #
  # Each step is a single ALTER TABLE, which MySQL applies completely or not at all:
  # 1. add each converted column as a stored generated column, so rows written
  #    during the conversion are converted too;
  # 2. in one statement, rename the original to *__old, turn the generated column
  #    into a regular one under the original name and rebuild the indexes.
  class V1Conversion
    class Error < StandardError; end

    INDEX_ATTRIBUTES = { length: :lengths, order: :orders, type: :type, using: :using, comment: :comment }.freeze

    def initialize(connection, table_name)
      @connection = connection
      @table_name = table_name.to_s
      @quoted_table = connection.quote_table_name(@table_name)
    end

    # @param columns [Array<ActiveRecord::ConnectionAdapters::Column>] 36-byte UUID columns
    # @param columns_options [Hash{String => Hash}] :limit, :null and :comment for converted columns
    def migrate(columns, columns_options = {})
      return if columns.empty?

      definitions = columns.to_h { |column| [column.name, definition(column, columns_options[column.name])] }
      refuse_keys!(columns)
      add_converted_columns(columns)
      remove_converted_columns_on_failure(columns) do
        alter_table(indexes_on(columns)) do
          columns.flat_map do |column|
            ["RENAME COLUMN #{quote(column.name)} TO #{quote(old_name(column))}",
             "CHANGE COLUMN #{quote(new_name(column))} #{quote(column.name)} #{definitions[column.name]}"]
          end
        end
      end
    end

    # @param columns [Array<ActiveRecord::ConnectionAdapters::Column>] converted columns that have an *__old column
    def rollback(columns)
      return if columns.empty?

      refuse_keys!(columns)
      refuse_stale_old_values!(columns)
      alter_table(indexes_on(columns)) do
        columns.flat_map do |column|
          ["DROP COLUMN #{quote(column.name)}", "RENAME COLUMN #{quote(old_name(column))} TO #{quote(column.name)}"]
        end
      end
    end

    private

    # Renaming a column moves its keys to the *__old column, which would silently drop them from the converted one.
    def refuse_keys!(columns)
      keyed = @connection.select_values(<<~SQL) & columns.map(&:name)
        SELECT COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = #{@connection.quote(@table_name)}
          AND (REFERENCED_TABLE_NAME IS NOT NULL OR CONSTRAINT_NAME = 'PRIMARY')
        UNION
        SELECT REFERENCED_COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE
        WHERE REFERENCED_TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME = #{@connection.quote(@table_name)}
      SQL
      raise Error, "#{keyed.join(', ')} in #{@table_name}: part of a primary or foreign key; drop the key first" if keyed.any?
    end

    # A rollback restores *__old, so it would lose rows written without the V1ModelMigration callbacks.
    def refuse_stale_old_values!(columns)
      columns.each do |column|
        stale = @connection.select_value(<<~SQL).to_i
          SELECT COUNT(*) FROM #{@quoted_table} WHERE NOT (#{quote(column.name)} <=> #{converted_value(old_name(column))})
        SQL
        raise Error, "#{stale} rows of #{@table_name}.#{column.name} differ from #{old_name(column)}; copy them first" unless stale.zero?
      end
    end

    def add_converted_columns(columns)
      @connection.change_table(@table_name, bulk: true) do |table|
        columns.each do |column|
          table.virtual new_name(column), type: :binary, limit: 16, as: converted_value(column.name), stored: true, after: column.name
        end
      end
    end

    def remove_converted_columns_on_failure(columns)
      yield
    rescue StandardError => e
      begin
        @connection.remove_columns(@table_name, *columns.map { |column| new_name(column) })
      rescue StandardError => cleanup_error
        warn "uuidable: could not remove the converted columns of #{@table_name}: #{cleanup_error.message}"
      end
      raise e
    end

    # 16-byte values are already binary. Anything else that is not a UUID makes UUID_TO_BIN fail the ALTER.
    def converted_value(column_name)
      column = quote(column_name)
      "IF(OCTET_LENGTH(#{column}) = 16, #{column}, UUID_TO_BIN(#{column}))"
    end

    def definition(column, options)
      options = { limit: 16, null: column.null, comment: column.comment }.merge((options || {}).transform_keys(&:to_sym))
      unknown = options.keys - %i[limit null comment]
      raise ArgumentError, "Unsupported options for #{column.name}: #{unknown.join(', ')}" if unknown.any?

      [@connection.type_to_sql(:binary, limit: options[:limit]),
       ('NOT NULL' unless options[:null]),
       ("COMMENT #{@connection.quote(options[:comment])}" if options[:comment])].compact.join(' ')
    end

    def indexes_on(columns)
      @connection.indexes(@table_name).select { |index| (Array(index.columns) & columns.map(&:name)).any? }
    end

    # Drops the indexes, applies the column changes and adds the indexes back in one statement.
    def alter_table(indexes)
      clauses = indexes.map { |index| "DROP INDEX #{quote(index.name)}" } + yield + indexes.map { |index| add_index_clause(index) }
      @connection.execute("ALTER TABLE #{@quoted_table} #{clauses.join(', ')}")
    end

    # Rails builds the clause it would use in change_table(bulk: true); its public API cannot be
    # combined with CHANGE COLUMN in a single statement.
    def add_index_clause(index)
      options = INDEX_ATTRIBUTES.transform_values { |reader| index.public_send(reader) }.reject { |_, value| value.nil? || value == {} }
      @connection.send(:add_index_for_alter, @table_name, index.columns, name: index.name, unique: index.unique, **options)
    end

    def new_name(column)
      "#{column.name}#{V1MigrationHelpers::NEW_POSTFIX}"
    end

    def old_name(column)
      "#{column.name}#{V1MigrationHelpers::OLD_POSTFIX}"
    end

    def quote(name)
      @connection.quote_column_name(name)
    end
  end
end
