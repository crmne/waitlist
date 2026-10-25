# Runs a product's approval step for one approved signup: register it with
# the product's webhook (Product#on_approve), email the person the approval
# email built from the webhook's answer (if the product has one), then tell
# the webhook it was sent. Each step is recorded, so a retry or the admin's
# "Try again" resumes where it stopped. Nothing the webhook returns is
# stored except its id: a key, for example, lives only in this job's memory
# and the email.
class ApprovalJob < ApplicationJob
  retry_on ApprovalWebhook::Error, wait: :polynomially_longer, attempts: 6
  discard_on ActiveJob::DeserializationError # the person was deleted meanwhile

  def perform(signup)
    product = signup.product
    return unless signup.approved_at && (config = product.on_approve)
    webhook = ApprovalWebhook.new(config, root: product.settings.fetch("root", Rails.root.to_s))

    template = product.approval_email_template
    if signup.approval_emailed_at.nil? && (template || signup.approval_registered_at.nil?)
      id, fields = webhook.register(signup)
      signup.update!(approval_reference: id, approval_registered_at: signup.approval_registered_at || Time.current)
      if template
        begin
          SignupMailer.approved(signup, product.approval_email_variables.merge(fields)).deliver_now
          signup.update!(approval_emailed_at: Time.current, approval_failed_at: nil)
        rescue StandardError
          signup.update!(approval_failed_at: Time.current)
          raise
        end
      end
    end

    if signup.approval_emailed_at && signup.approval_acknowledged_at.nil? && webhook.acknowledges?
      webhook.acknowledge(signup)
      signup.update!(approval_acknowledged_at: Time.current)
    end
  end
end
