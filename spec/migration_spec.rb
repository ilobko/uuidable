# frozen_string_literal: true

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

RSpec.shared_examples 'UUID column storage' do |method, column_method, table_args|
  {
    'no storage' => [{}, 16],
    'binary storage' => [{ storage: :binary }, 16],
    'text storage' => [{ storage: :text }, 36],
    'an explicit limit' => [{ limit: 36 }, 36]
  }.each do |label, (options, expected_limit)|
    context "with #{label}" do
      let(:receiver) { Object.new.extend(described_class) }

      before do
        allow(receiver).to receive(column_method)
        allow(receiver).to receive(:index)
        allow(receiver).to receive(:add_index)
        receiver.public_send(method, *table_args, **options)
      end

      it "creates a #{expected_limit}-byte column" do
        expect(receiver).to have_received(column_method).with(*table_args, :uuid, :binary, limit: expected_limit, null: false)
      end
    end
  end
end

RSpec.describe Uuidable::TableDefinition do
  include_examples 'UUID column storage', :uuid, :column, []
end

RSpec.describe Uuidable::Migration do
  include_examples 'UUID column storage', :add_uuid_column, :add_column, [:records]
end

RSpec.describe Uuidable, '.column_options' do
  subject(:options) { described_class.column_options(given) }

  context 'with text as the default storage' do
    around do |example|
      described_class.default_storage = :text
      example.run
    ensure
      described_class.default_storage = :binary
    end

    {
      'no storage' => [{}, 36],
      'binary storage' => [{ storage: :binary }, 16],
      'an explicit limit' => [{ limit: 16 }, 16]
    }.each do |label, (options, expected_limit)|
      context "with #{label}" do
        let(:given) { options }

        it { is_expected.to include(limit: expected_limit) }
      end
    end
  end

  context 'with storage that conflicts with the limit' do
    let(:given) { { storage: :binary, limit: 36 } }

    it { expect { options }.to raise_error(ArgumentError, /conflicts/) }
  end

  context 'with unknown storage' do
    let(:given) { { storage: :uuid } }

    it { expect { options }.to raise_error(ArgumentError, /must be one of/) }
  end
end

RSpec.describe Uuidable, '.default_storage=' do
  it 'rejects unknown storage' do
    expect { described_class.default_storage = :uuid }.to raise_error(ArgumentError)
  end
end
