# One attempt per step, with a fresh product-side check immediately before
# sending. A claim prevents duplicate jobs sending twice. No network request
# or SMTP delivery holds a database transaction open.
class ApprovalFollowUpJob < ApplicationJob
  retry_on ApprovalWebhook::Error, wait: :polynomially_longer, attempts: 6
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  def perform(signup, step = 1)
    columns = Signup.follow_up_columns(step)
    signup.reload
    product = signup.product.reload
    return unless product.approval_follow_up_due(step).exists?(signup.id)

    webhook = ApprovalWebhook.new(product.on_approve, root: product.settings.fetch("root", Rails.root.to_s))
    eligible = webhook.follow_up?(signup)
    # Read/render the template before claiming so a broken deployment can be
    # repaired without consuming the one attempt. The message is memory-only.
    if eligible
      delivery = SignupMailer.approval_follow_up(signup, step)
      delivery.message
    end
    claimed = product.reload.approval_follow_up_due(step).where(id: signup.id)
      .update_all(columns.fetch(:checked) => Time.current)
    return unless claimed == 1 && eligible

    # Leaving the list deletes the signup. Also recheck an approval revoked
    # while the webhook was running, and a product disabled meanwhile.
    signup.reload
    return unless signup.confirmed? && signup.approved_at && signup.product.reload.approval_follow_up_step(step)

    begin
      delivery.deliver_now
      signup.update!(columns.fetch(:sent) => Time.current)
    rescue StandardError
      Signup.where(id: signup.id).update_all(columns.fetch(:failed) => Time.current)
      # Keep the claim: an SMTP error may mean the server accepted the email
      # but its reply was lost. Never retry a possibly delivered follow-up.
      raise
    end
  end
end
