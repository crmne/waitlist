# The deletion periods in docs/privacy.md, run daily (config/recurring.yml).
class RetentionJob < ApplicationJob
  def perform(now: Time.current)
    # Unconfirmed: a week after signing up, or by their confirm_by date if
    # they were imported and sent one reminder.
    Signup.unconfirmed.where(confirm_by: nil, created_at: ...(now - Rails.configuration.x.unconfirmed_retention)).delete_all
    Signup.unconfirmed.where(confirm_by: ...now).delete_all
    Product.find_each do |product|
      product.signups.approved.where(approved_at: ...(now - product.keep_approved_days.days)).delete_all
    end
  end
end
