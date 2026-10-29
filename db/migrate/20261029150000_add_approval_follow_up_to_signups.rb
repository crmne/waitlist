class AddApprovalFollowUpToSignups < ActiveRecord::Migration[8.1]
  def change
    add_column :signups, :approval_follow_up_checked_at, :datetime
    add_column :signups, :approval_follow_up_sent_at, :datetime
    add_column :signups, :approval_follow_up_failed_at, :datetime
  end
end
