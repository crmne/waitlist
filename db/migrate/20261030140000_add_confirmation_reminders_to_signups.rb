class AddConfirmationRemindersToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :confirmation_reminder_checked_at, :datetime
    add_column :signups, :confirmation_reminder_sent_at, :datetime
    add_column :signups, :confirmation_reminder_failed_at, :datetime
    add_column :signups, :confirmation_reminder_second_checked_at, :datetime
    add_column :signups, :confirmation_reminder_second_sent_at, :datetime
    add_column :signups, :confirmation_reminder_second_failed_at, :datetime
  end
end
