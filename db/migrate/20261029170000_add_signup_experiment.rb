class AddSignupExperiment < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :experiment, :string
    add_column :signups, :variant, :string
    add_index :signups, [:product_id, :experiment, :variant]
  end
end
