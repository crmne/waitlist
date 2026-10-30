# The deletion periods in docs/privacy.md, run daily (config/recurring.yml).
class RetentionJob < ApplicationJob
  def perform(now: Time.current)
    # Explicit deadlines cover imports and confirmation reminders. Other
    # signups use their product's window (14 days with reminders, otherwise 7).
    Signup.unconfirmed.where(confirm_by: ...now).delete_all
    Product.find_each do |product|
      product.signups.unconfirmed.where(confirm_by: nil, created_at: ...(now - product.unconfirmed_retention)).delete_all
      product.signups.approved.where(approved_at: ...(now - product.keep_approved_days.days)).delete_all
    end
  end
end
