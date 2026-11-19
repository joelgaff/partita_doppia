# A `matching(text)` scope: rows where any of the named columns contains the
# text, case aside. LIKE's own wildcards are escaped, so "%" is just a
# character.
#
#   searchable_by :name, :email, :phone
module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def searchable_by(*columns)
      scope :matching, ->(text) {
        pattern = "%#{sanitize_sql_like(text.to_s.strip)}%"
        where(columns.map { |column| "#{quoted_table_name}.#{connection.quote_column_name(column)} LIKE :p ESCAPE '\\'" }.join(" OR "), p: pattern)
      }
    end
  end
end
