# frozen_string_literal: true

# Defines throwaway models with unique constant names. Rails 6.1 caches
# association classes by name, so specs must not reuse a name for a different class.
module UuidableSpecModels
  def define_model(name, table_name, &body)
    Class.new(ActiveRecord::Base).tap do |model|
      Object.const_set(name, model)
      model.table_name = table_name
      model.class_eval(&body) if body
    end
  end

  def remove_models(*names)
    names.each { |name| Object.send(:remove_const, name) if Object.const_defined?(name, false) }
  end

  def rollback_each_example
    around do |example|
      ActiveRecord::Base.transaction do
        example.run
        raise ActiveRecord::Rollback
      end
    end
  end
end

RSpec.configure do |config|
  config.extend UuidableSpecModels
  config.include UuidableSpecModels
end
