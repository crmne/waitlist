# Emails the product's `notify` address that someone confirmed their signup.
# A job, so a mail failure never breaks the confirm page; retried with
# backoff, and dropped if the person left in the meantime.
class NotifyJoinedJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 8
  discard_on ActiveJob::DeserializationError

  def perform(signup)
    return unless signup.confirmed? && signup.product.notify_address
    OwnerMailer.joined(signup).deliver_now
  end
end
