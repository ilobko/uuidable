# frozen_string_literal: true

require 'spec_helper'

RSpec.shared_context 'with a pre-v1 table' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration_class) do
    Class.new(ActiveRecord::Migration[ActiveRecord::Migration.current_version]) { include Uuidable::V1MigrationHelpers }
  end
  let(:migration) { migration_class.new }
  let(:record_uuid) { '01234567-89ab-4cde-8fab-0123456789ab' }
  let(:reference_uuid) { 'fedcba98-7654-4321-8fed-cba987654321' }
  let(:other_uuid) { 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' }
  let(:columns) { connection.columns(:uuidable_conversions).map { |column| [column.name, column.limit, column.null] } }
  let(:indexes) { connection.indexes(:uuidable_conversions).to_h { |index| [index.name, [index.columns, index.unique]] } }
  let(:rows) do
    connection.select_rows(<<~SQL)
      SELECT IF(OCTET_LENGTH(uuid) = 16, BIN_TO_UUID(uuid), uuid), IF(OCTET_LENGTH(reference_uuid) = 16, BIN_TO_UUID(reference_uuid), reference_uuid)
      FROM uuidable_conversions ORDER BY id
    SQL
  end

  before do
    connection.create_table(:uuidable_conversions) do |t|
      t.uuid limit: 36, index: { name: 'conversion_uuid' }
      t.uuid :reference_uuid, limit: 36, null: true, index: { name: 'conversion_reference', unique: false }
      t.string :name
    end
    connection.execute(<<~SQL)
      INSERT INTO uuidable_conversions (uuid, reference_uuid, name)
      VALUES ('#{record_uuid}', '#{reference_uuid}', 'first'), ('#{other_uuid}', NULL, 'second')
    SQL
  end

  after { connection.drop_table(:uuidable_conversions) }
end

RSpec.describe Uuidable::V1MigrationHelpers, :mysql do
  include_context 'with a pre-v1 table'

  let(:original_rows) { [[record_uuid, reference_uuid], [other_uuid, nil]] }
  let(:original_indexes) { { 'conversion_uuid' => [['uuid'], true], 'conversion_reference' => [['reference_uuid'], false] } }

  describe '#uuidable_migrate_uuid_columns_to_v1' do
    context 'without a column list' do
      let(:old_values) { connection.select_rows('SELECT uuid__old, reference_uuid__old FROM uuidable_conversions ORDER BY id') }

      before { migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions) }

      it 'converts every UUID column and keeps the originals' do
        expect(columns).to eq([['id', 8, false], ['uuid__old', 36, false], ['uuid', 16, false],
                               ['reference_uuid__old', 36, true], ['reference_uuid', 16, true], ['name', 255, true]])
      end

      it 'keeps the values' do
        expect(rows).to eq(original_rows)
      end

      it 'keeps the original values in the old columns' do
        expect(old_values).to eq(original_rows)
      end

      it 'rebuilds the indexes on the converted columns' do
        expect(indexes).to eq(original_indexes)
      end
    end

    context 'with a column list' do
      before { migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions, { 'reference_uuid' => { null: true } }) }

      it 'converts only the listed columns' do
        expect(columns.map(&:first)).to eq(%w[id uuid reference_uuid__old reference_uuid name])
      end
    end
  end

  describe '#uuidable_rollback_uuid_columns_from_v1' do
    before do
      migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
      migration.uuidable_rollback_uuid_columns_from_v1(:uuidable_conversions)
    end

    it 'restores the original columns' do
      expect(columns).to eq([['id', 8, false], ['uuid', 36, false], ['reference_uuid', 36, true], ['name', 255, true]])
    end

    it 'restores the values' do
      expect(rows).to eq(original_rows)
    end

    it 'restores the indexes' do
      expect(indexes).to eq(original_indexes)
    end
  end

  describe '#uuidable_drop_all_pre_v1_uuid_columns!' do
    before do
      migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
      migration.uuidable_drop_all_pre_v1_uuid_columns!
    end

    it 'drops the old columns' do
      expect(columns.map(&:first)).to eq(%w[id uuid reference_uuid name])
    end

    it 'keeps the converted values' do
      expect(rows).to eq(original_rows)
    end
  end
end

RSpec.describe Uuidable::V1MigrationHelpers, 'safety', :mysql do
  include_context 'with a pre-v1 table'

  let(:original_columns) { [['id', 8, false], ['uuid', 36, false], ['reference_uuid', 36, true], ['name', 255, true]] }
  let(:original_indexes) { { 'conversion_uuid' => [['uuid'], true], 'conversion_reference' => [['reference_uuid'], false] } }

  describe '#uuidable_migrate_uuid_columns_to_v1' do
    context 'with a column comment and index options' do
      let(:comment) { connection.columns(:uuidable_conversions).find { |column| column.name == 'uuid' }.comment }
      let(:index) { connection.indexes(:uuidable_conversions).find { |item| item.name == 'conversion_reference' } }

      before do
        connection.change_column_comment(:uuidable_conversions, :uuid, 'Public UUID')
        connection.remove_index(:uuidable_conversions, name: 'conversion_reference')
        connection.add_index(:uuidable_conversions, %i[reference_uuid name], name: 'conversion_reference',
                                                                             length: { reference_uuid: 8 }, order: { name: :desc })
        migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
      end

      it 'keeps the comment' do
        expect(comment).to eq('Public UUID')
      end

      it 'keeps the index options' do
        expect([index.columns, index.lengths, index.orders])
          .to eq([%w[reference_uuid name], { 'reference_uuid' => 8 }, { 'name' => :desc }])
      end
    end

    context 'with an empty options hash for a nullable column' do
      before { migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions, { 'reference_uuid' => {} }) }

      it 'keeps the column nullable' do
        expect(columns).to include(['reference_uuid', 16, true])
      end
    end

    context 'with UUIDs that differ only in case' do
      before { connection.execute("INSERT INTO uuidable_conversions (uuid) VALUES ('#{record_uuid.upcase}')") }

      it 'fails without changing the table' do
        expect { migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions) }.to raise_error(ActiveRecord::RecordNotUnique)
        expect([columns, indexes]).to eq([original_columns, original_indexes])
      end
    end

    ['abc', 'not-a-uuid-and-longer-than-16'].each do |value|
      context "with #{value.inspect} in a UUID column" do
        before { connection.execute("UPDATE uuidable_conversions SET reference_uuid = '#{value}' WHERE name = 'second'") }

        it 'fails without changing the table' do
          expect { migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions) }
            .to raise_error(ActiveRecord::StatementInvalid, /Incorrect string value/)
          expect([columns, indexes]).to eq([original_columns, original_indexes])
        end
      end
    end

    context 'with writes during the conversion' do
      let(:late_uuid) { 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff' }

      before do
        alters = 0
        allow(connection).to receive(:execute).and_wrap_original do |execute, sql, *args|
          alters += 1 if sql.start_with?('ALTER TABLE')
          if alters == 2 && sql.start_with?('ALTER TABLE')
            execute.call("INSERT INTO uuidable_conversions (uuid, reference_uuid) VALUES ('#{late_uuid}', '#{record_uuid}')")
            execute.call("UPDATE uuidable_conversions SET reference_uuid = '#{other_uuid}' WHERE name = 'first'")
          end
          execute.call(sql, *args)
        end
        migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
      end

      it 'converts them as well' do
        expect(rows).to eq([[record_uuid, other_uuid], [other_uuid, nil], [late_uuid, record_uuid]])
      end
    end

    context 'with a foreign key' do
      before do
        connection.create_table(:uuidable_conversion_children) { |t| t.uuid :parent_uuid, limit: 36, index: false }
        connection.add_foreign_key(:uuidable_conversion_children, :uuidable_conversions, column: :parent_uuid, primary_key: :uuid)
      end

      after { connection.drop_table(:uuidable_conversion_children) }

      it 'refuses to convert the referenced column' do
        expect { migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions) }
          .to raise_error(Uuidable::V1Conversion::Error, /foreign key/)
        expect(columns).to eq(original_columns)
      end
    end

    context 'when a reversible migration is rolled back' do
      let(:reversible_migration) do
        Class.new(migration_class) do
          def change
            uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
          end
        end.new
      end

      before do
        reversible_migration.migrate(:up)
        reversible_migration.migrate(:down)
      end

      it 'restores the original columns' do
        expect([columns, rows]).to eq([original_columns, [[record_uuid, reference_uuid], [other_uuid, nil]]])
      end
    end
  end

  describe '#uuidable_rollback_uuid_columns_from_v1' do
    context 'when a row changed without the transition callbacks' do
      before do
        migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
        connection.execute("UPDATE uuidable_conversions SET reference_uuid = UUID_TO_BIN('#{other_uuid}') WHERE name = 'first'")
      end

      it 'refuses to lose the change' do
        expect { migration.uuidable_rollback_uuid_columns_from_v1(:uuidable_conversions) }
          .to raise_error(Uuidable::V1Conversion::Error, /1 rows of uuidable_conversions\.reference_uuid differ/)
        expect(columns.map(&:first)).to include('reference_uuid__old')
      end
    end

    context 'with a column that was created with 16 bytes' do
      before do
        connection.add_column(:uuidable_conversions, :external_uuid, :binary, limit: 16)
        migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
        migration.uuidable_rollback_uuid_columns_from_v1(:uuidable_conversions)
      end

      it 'leaves it alone' do
        expect(columns).to eq(original_columns + [['external_uuid', 16, true]])
      end
    end
  end

  describe '#uuidable_drop_all_pre_v1_uuid_columns!' do
    before do
      connection.add_column(:uuidable_conversions, :notes__old, :string)
      migration.uuidable_migrate_uuid_columns_to_v1(:uuidable_conversions)
      migration.uuidable_drop_all_pre_v1_uuid_columns!
    end

    it 'keeps columns that are not UUIDs' do
      expect(columns.map(&:first)).to eq(%w[id uuid reference_uuid name notes__old])
    end
  end
end
