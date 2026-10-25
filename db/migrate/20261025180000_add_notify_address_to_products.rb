class AddNotifyAddressToProducts < ActiveRecord::Migration[8.1]
  def change
    # Where "someone joined" emails go when a signup confirms (blank: none).
    add_column :products, :notify_address, :string
  end
end
