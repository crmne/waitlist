# Runs the product's approval step (LicenceIssuers) for one approved signup.
class ApprovalJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 8
  discard_on ActiveJob::DeserializationError # the person was deleted meanwhile

  def perform(signup)
    return unless signup.approved_at && signup.licence_issued_at.nil?
    issuer = signup.product.licence_issuer or return
    reference = issuer.issue(signup)
    signup.update!(licence_issued_at: Time.current, licence_reference: reference.to_s) if reference.present?
  end
end
