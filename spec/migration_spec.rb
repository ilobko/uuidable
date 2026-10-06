# frozen_string_literal: true

require 'logger'
require 'active_record'
require 'spec_helper'

RSpec.shared_examples 'UUID column names' do |method, column_method, table_args|
  {
    'default name' => [[], {}, :uuid, { limit: 16, null: false }],
    'positional name' => [[:external_uuid], {}, :external_uuid, { limit: 16, null: false }],
    'keyword name' => [[], { column_name: :external_uuid, limit: 36, null: true }, :external_uuid, { limit: 36, null: true }],
    'nil and keyword name' => [[nil], { column_name: :external_uuid }, :external_uuid, { limit: 16, null: false }],
    'name given both ways' => [[:external_uuid], { column_name: 'external_uuid' }, :external_uuid, { limit: 16, null: false }],
    'nil name' => [[nil], {}, :uuid, { limit: 16, null: false }]
  }.each do |label, (name_args, options, expected_name, expected_options)|
    context "with a #{label}" do
      let(:receiver) { Object.new.extend(described_class) }

      before do
        allow(receiver).to receive(column_method)
        allow(receiver).to receive(:index)
        allow(receiver).to receive(:add_index)
        receiver.public_send(method, *table_args, *name_args, **options)
      end

      it 'consumes the name and forwards the column options' do
        expect(receiver).to have_received(column_method).with(*table_args, expected_name, :binary, **expected_options)
      end
    end
  end
end

RSpec.describe Uuidable::TableDefinition do
  include_examples 'UUID column names', :uuid, :column, []
end

RSpec.describe Uuidable::Migration do
  include_examples 'UUID column names', :add_uuid_column, :add_column, [:records]
end

RSpec.describe Uuidable, '.column_name' do
  it 'refuses two different names' do
    expect { described_class.column_name(:other_uuid, :external_uuid) }.to raise_error(ArgumentError, /named twice/)
  end
end
