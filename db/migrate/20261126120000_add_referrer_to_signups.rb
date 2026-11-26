class AddReferrerToSignups < ActiveRecord::Migration[8.1]
  def change
    # A fixed class of the page someone came from (chatgpt, search, reddit...),
    # never the address itself.
    add_column :signups, :referrer, :string
  end
end
