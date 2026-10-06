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
