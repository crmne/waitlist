class AddSecondApprovalFollowUpToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :approval_follow_up_second_checked_at, :datetime
    add_column :signups, :approval_follow_up_second_sent_at, :datetime
    add_column :signups, :approval_follow_up_second_failed_at, :datetime
  end
end
