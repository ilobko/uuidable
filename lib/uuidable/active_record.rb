# frozen_string_literal: true

module Uuidable
  # ActiveRecord mixin
  module ActiveRecord
    extend ActiveSupport::Concern

    class UuidChangeError < RuntimeError; end

    module Finder
      def find(*args)
        if args.first.is_a?(String) && args.first&.match(UUIDTools::UUID_REGEXP)
          find_by_uuid!(*args)
        else
          super
        end
      end
    end

    # Reads 16-byte UUID columns as UUID strings. The types are installed when the
    # model loads its schema, so defining a model needs no database connection.
    module SchemaTypes
      # Rails 7.2 started asking the model for the type of each column.
      def self.type_for_column_hook?
        ::ActiveRecord::ModelSchema::ClassMethods.private_method_defined?(:type_for_column)
      end

      private

      def load_schema!
        super
        install_uuid_types unless SchemaTypes.type_for_column_hook?
        include V1ModelMigration if columns_hash.each_key.any? { |name| name.include?(V1MigrationHelpers::OLD_POSTFIX) }
      end

      def type_for_column(connection, column)
        uuid_column?(connection, column) ? MySQLBinUUID::Type.new : super
      end

      # Before Rails 7.2: replace the schema types, keeping types declared with `attribute`.
      def install_uuid_types
        columns_hash.each_value do |column|
          next if !uuid_column?(connection, column) || attributes_to_define_after_schema_loads.key?(column.name)

          define_attribute(column.name, MySQLBinUUID::Type.new, default: column.default, user_provided_default: false)
        end
      end

      def uuid_column?(connection, column)
        column.type == :binary && column.limit == 16 && column.name.include?('uuid') &&
          connection.adapter_name.downcase.include?('mysql')
      end
    end

    # ClassMethods
    module ClassMethods
      include Finder

      def uuidable(as_param: true) # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
        singleton_class.prepend(SchemaTypes) unless singleton_class.include?(SchemaTypes)
        reload_schema_from_cache if schema_loaded?

        after_initialize do
          self.uuid = Uuidable.generate_uuid if attributes.keys.include?('uuid') && uuid.blank?
        end

        validates :uuid, presence: true, uniqueness: true, if: -> { try :uuid_changed? }

        if as_param
          define_method :to_param do
            uuid
          end
        end

        define_method :uuid= do |val|
          raise UuidChangeError, 'Uuid changing is bad idea!' unless new_record? || uuid.blank? || uuid == val

          super(val)
        end
      end
    end

    def short_uuid
      UUIDTools::UUID.parse(uuid).hexdigest
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Base.include Uuidable::ActiveRecord
  ActiveRecord::Relation.prepend Uuidable::ActiveRecord::Finder
end
