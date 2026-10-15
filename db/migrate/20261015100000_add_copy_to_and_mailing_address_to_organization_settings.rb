class AddCopyToAndMailingAddressToOrganizationSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_settings, :email_copy_to, :string
    add_column :organization_settings, :mailing_address, :text
  end
end
