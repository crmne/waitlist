class AddReferrals < ActiveRecord::Migration[8.1]
  def change
    # Each signup's personal referral code, who referred it, and how many of
    # the people it referred confirmed. Who referred whom is kept only to
    # order the line; nobody is shown who joined through their link.
    add_column :signups, :referral_code, :string
    add_reference :signups, :referred_by, foreign_key: { to_table: :signups, on_delete: :nullify }
    add_column :signups, :referrals_count, :integer, null: false, default: 0
    # Referral credit carried over from GetWaitlist that has no matching
    # person here (for example someone who never confirmed there).
    add_column :signups, :imported_referrals, :integer, null: false, default: 0
    add_index :signups, [:product_id, :referral_code], unique: true

    add_column :products, :places_per_referral, :integer, null: false, default: 5
  end
end
