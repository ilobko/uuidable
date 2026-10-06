# Uuidable

[![Build](https://github.com/flant/uuidable/actions/workflows/ruby.yml/badge.svg)](https://github.com/flant/uuidable/actions/workflows/ruby.yml) [![Gem Version](https://badge.fury.io/rb/uuidable.svg)](https://badge.fury.io/rb/uuidable)

With this gem you can use UUID instead of id in routes. But id is still primary key.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'uuidable'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install uuidable

## Usage

Simply add `uuidable` in your ActiveRecord model:

```ruby
class Project < ActiveRecord::Base
    uuidable

    # Rest of the code
end
```

You can use special methods in migrations:
```ruby
class CreateProjects < ActiveRecord::Migration
    def change
        create_table :projects do |t|
            t.uuid
            #...
        end
        # Or
        add_uuid_column :projects
    end
end
```

## UUID storage

New UUID columns store 16 bytes (`varbinary(16)`). Versions before 1.0 stored the 36-character text form (`varbinary(36)`). Models read both as UUID strings (16-byte columns are recognized by `uuid` in their name), and upgrading the gem does not change existing columns.

Choose the format of a new column with `storage:`:

```ruby
t.uuid storage: :text
add_uuid_column :projects, :parent_uuid, storage: :binary
```

An app that keeps its pre-1.0 columns can make text the default, so that new columns match the existing ones:

```ruby
# config/initializers/uuidable.rb
Uuidable.default_storage = :text
```

Columns compared in SQL, for example in a join, must use the same storage: a 16-byte UUID never equals its 36-character text form.

## Converting pre-1.0 columns

Converting existing columns is optional. On MySQL 8, include the helpers in a migration:

```ruby
class ConvertProjectUuids < ActiveRecord::Migration[7.2]
  include Uuidable::V1MigrationHelpers

  def change
    # Every 36-byte column with `uuid` in its name, or only the listed ones:
    uuidable_migrate_uuid_columns_to_v1 :projects
    uuidable_migrate_uuid_columns_to_v1 :tasks, { 'project_uuid' => {} }
  end
end
```

The original values stay in `*__old` columns, which models keep writing while they exist, so the migration can be rolled back. When you no longer need that, drop them with `uuidable_drop_all_pre_v1_uuid_columns!`; this cannot be undone.

- Each step is a single `ALTER TABLE`. If the conversion fails, for example on a value that is not a UUID or on two UUIDs that differ only in case under a unique index, the table is left unchanged.
- Rows written during the conversion are converted too, but adding the converted columns rebuilds the table and blocks writes meanwhile. Restart the application afterwards: running processes keep the old column types.
- Columns that are part of a primary or foreign key are refused; drop the key first.
- A rollback is refused if rows changed without the model callbacks, for example with `update_all`, because the `*__old` columns miss those changes. Inserts that skip callbacks, such as `insert_all`, fail while a `NOT NULL` `*__old` column exists.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Specs that need a database are skipped unless `UUIDABLE_DATABASE_URL` points to a MySQL 8 database whose name ends in `_test`. The specs create and drop their own tables. To run them against a specific Active Record version:

    BUNDLE_GEMFILE=gemfiles/activerecord.gemfile ACTIVE_RECORD_VERSION='~> 8.1.0' \
      UUIDABLE_DATABASE_URL=mysql2://root@127.0.0.1:3306/uuidable_test bundle exec rake

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flant/uuidable.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
