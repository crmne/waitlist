class CreateProductsAndSignups < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :slug, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :site_url, null: false
      t.string :privacy_url, null: false
      t.string :from_address, null: false
      t.string :reply_to
      t.json :allowed_origins, null: false, default: []
      t.string :thanks_url
      t.string :approval
      t.integer :keep_approved_days, null: false, default: 90
      t.json :questions, null: false, default: []
      t.timestamps
    end

    # No IP address, user agent, referrer or referral data, by design
    # (docs/privacy.md).
    create_table :signups do |t|
      t.references :product, null: false, foreign_key: true
      t.string :email, null: false
      t.json :answers, null: false, default: {}
      t.string :source, null: false, default: "form"
      t.string :consent_text, null: false
      t.datetime :confirmation_sent_at
      t.datetime :confirmed_at
      t.datetime :approved_at
      t.datetime :licence_issued_at
      t.string :licence_reference
      t.timestamps
      t.index [:product_id, :email], unique: true
      t.index [:product_id, :confirmed_at, :approved_at, :created_at]
    end

    # Someone who left or asked to be deleted: a keyed digest of the address,
    # so an import never adds them back. Signing up again lifts it.
    create_table :suppressions do |t|
      t.references :product, null: false, foreign_key: true
      t.string :email_digest, null: false
      t.datetime :created_at, null: false
      t.index [:product_id, :email_digest], unique: true
    end
  end
end
