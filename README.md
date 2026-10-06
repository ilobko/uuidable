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
