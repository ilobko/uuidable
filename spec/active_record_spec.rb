# frozen_string_literal: true

require 'spec_helper'

RSpec.shared_context 'with UUID models' do |limit|
  let(:connection) { ActiveRecord::Base.connection }
  let(:known_uuid) { '01234567-89ab-4cde-8fab-0123456789ab' }
  let(:other_uuid) { 'fedcba98-7654-4321-8fed-cba987654321' }
  let(:model) { Object.const_get("UuidableRecord#{limit}") }
  let(:reference_model) { Object.const_get("UuidableReference#{limit}") }

  before(:all) do
    ActiveRecord::Base.connection.create_table(:uuidable_records) { |t| t.uuid limit: limit }
    ActiveRecord::Base.connection.create_table(:uuidable_references) do |t|
      t.uuid :record_uuid, limit: limit, null: true, index: false
    end

    define_model("UuidableRecord#{limit}", 'uuidable_records') { uuidable }
    define_model("UuidableReference#{limit}", 'uuidable_references') do
      uuidable as_param: false
      belongs_to :record, class_name: "UuidableRecord#{limit}", primary_key: :uuid, foreign_key: :record_uuid, optional: true
    end
  end

  after(:all) do
    remove_models("UuidableRecord#{limit}", "UuidableReference#{limit}")
    ActiveRecord::Base.connection.drop_table(:uuidable_references)
    ActiveRecord::Base.connection.drop_table(:uuidable_records)
  end

  rollback_each_example
end

RSpec.shared_examples 'a UUID model' do |limit|
  include_context 'with UUID models', limit

  describe 'a new record' do
    subject(:record) { model.new }

    it 'gets a generated UUID' do
      expect(record.uuid).to match(UUIDTools::UUID_REGEXP)
    end
  end

  describe 'a saved record' do
    subject!(:record) { model.create!(uuid: known_uuid) }

    let(:stored_size) { connection.select_value("SELECT OCTET_LENGTH(uuid) FROM uuidable_records WHERE id = #{record.id}") }

    it 'reloads the same UUID string' do
      expect(record.reload.uuid).to eq(known_uuid)
    end

    it "stores #{limit} bytes" do
      expect(stored_size).to eq(limit)
    end

    it 'is found by its UUID' do
      expect(model.find(known_uuid)).to eq(record)
    end

    it 'is found by its id' do
      expect(model.find(record.id)).to eq(record)
    end

    it 'uses the UUID as a route parameter' do
      expect(record.to_param).to eq(known_uuid)
    end

    it 'shortens the UUID' do
      expect(record.short_uuid).to eq(known_uuid.delete('-'))
    end

    it 'refuses to change the UUID' do
      expect { record.uuid = other_uuid }.to raise_error(Uuidable::ActiveRecord::UuidChangeError)
    end
  end

  describe 'a record with a duplicate UUID' do
    subject(:duplicate) { model.new(uuid: known_uuid) }

    before { model.create!(uuid: known_uuid) }

    it { is_expected.not_to be_valid }
  end

  describe 'a reference by UUID' do
    subject!(:reference) { reference_model.create!(record_uuid: known_uuid).reload }

    let!(:record) { model.create!(uuid: known_uuid) }

    it 'reads the referenced UUID' do
      expect(reference.record_uuid).to eq(known_uuid)
    end

    it 'resolves the association' do
      expect(reference.record).to eq(record)
    end

    it 'joins on the UUID' do
      expect(reference_model.joins(:record).pluck(:id)).to eq([reference.id])
    end

    it 'uses the id as a route parameter when as_param is disabled' do
      expect(reference.to_param).to eq(reference.id.to_s)
    end
  end
end

RSpec.describe Uuidable::ActiveRecord, :mysql do
  context 'with 36-byte text UUIDs' do
    it_behaves_like 'a UUID model', 36
  end

  context 'with 16-byte binary UUIDs' do
    it_behaves_like 'a UUID model', 16
  end

  context 'with a retained pre-v1 column' do
    subject(:record) { UuidableTransitionRecord.create!(uuid: '01234567-89ab-4cde-8fab-0123456789ab').reload }

    before(:all) do
      ActiveRecord::Base.connection.create_table(:uuidable_transition_records) do |t|
        t.uuid
        t.binary :uuid__old, limit: 36, null: false
      end
      define_model('UuidableTransitionRecord', 'uuidable_transition_records') { uuidable }
    end

    after(:all) do
      remove_models('UuidableTransitionRecord')
      ActiveRecord::Base.connection.drop_table(:uuidable_transition_records)
    end

    rollback_each_example

    it 'keeps writing the old column' do
      expect(record.uuid__old).to eq(record.uuid)
    end
  end
end

RSpec.describe Uuidable::ActiveRecord, '.uuidable', :mysql do
  let(:connection) { ActiveRecord::Base.connection }
  let(:known_uuid) { '01234567-89ab-4cde-8fab-0123456789ab' }

  after do
    remove_models('UuidableEarlyRecord', 'UuidableUnreachableRecord', 'UuidableTypedRecord')
    connection.drop_table(:uuidable_late_records, if_exists: true)
  end

  context 'when the model is defined before its table exists' do
    subject(:record) { UuidableEarlyRecord.create!(uuid: known_uuid).reload }

    before do
      define_model('UuidableEarlyRecord', 'uuidable_late_records') { uuidable }
      connection.create_table(:uuidable_late_records, &:uuid)
    end

    it 'reads the binary UUID as a string' do
      expect(record.uuid).to eq(known_uuid)
    end
  end

  context 'when the database is unreachable' do
    subject(:definition) do
      lambda do
        define_model('UuidableUnreachableRecord', 'uuidable_unreachable_records') do
          establish_connection(adapter: 'mysql2', host: '127.0.0.1', port: 1, database: 'uuidable_unreachable_test')
          uuidable
        end
      end
    end

    after { UuidableUnreachableRecord.remove_connection if Object.const_defined?(:UuidableUnreachableRecord) }

    it 'still defines the model' do
      expect(&definition).not_to raise_error
    end
  end

  context 'when the model declares its own type for a UUID column' do
    subject(:type) { UuidableTypedRecord.type_for_attribute('uuid') }

    before do
      connection.create_table(:uuidable_late_records, &:uuid)
      define_model('UuidableTypedRecord', 'uuidable_late_records') do
        uuidable
        attribute :uuid, ActiveModel::Type::Binary.new
      end
    end

    it 'keeps the declared type' do
      expect(type).to be_an_instance_of(ActiveModel::Type::Binary)
    end
  end
end
