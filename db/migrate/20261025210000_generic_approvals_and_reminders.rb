class GenericApprovalsAndReminders < ActiveRecord::Migration[8.1]
  def change
    # The approval step is a generic webhook now (Product#on_approve), not a
    # licence call: name its columns for what they are.
    rename_column :signups, :licence_issued_at, :approval_registered_at
    rename_column :signups, :licence_reference, :approval_reference
    add_column :signups, :approval_emailed_at, :datetime
    add_column :signups, :approval_acknowledged_at, :datetime
    add_column :signups, :approval_failed_at, :datetime

    # Someone imported unconfirmed and sent one reminder: deleted after this
    # unless they confirm (RetentionJob).
    add_column :signups, :reminder_sent_at, :datetime
    add_column :signups, :confirm_by, :datetime

    # Brand, approval webhook and email, reminder period: everything a
    # product configures beyond the basics, as given in its products file.
    add_column :products, :settings, :json, null: false, default: {}
  end
end
