class AddExistingUserToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :existing_user, :boolean, default: false, null: false
  end
end
