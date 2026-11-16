class Current < ActiveSupport::CurrentAttributes
  # Single-tenant today; repoint resolution when multi-tenancy activates.
  attribute :organization
  attribute :user
  attribute :importing   # true while an importer runs: history comes in as it was (see Imports::BaseService)
end
