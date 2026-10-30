# At most one attempt per step. Never automatically retry an uncertain SMTP
# result: the server may have accepted the message before disconnecting.
class ConfirmationReminderJob < ApplicationJob
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  def perform(signup, step = 1)
    columns = Signup.confirmation_reminder_columns(step)
    signup.reload
    product = signup.product.reload
    return unless product.confirmation_reminder_due(step).exists?(signup.id)

    # Leave a week to act after the final reminder, including delayed jobs.
    # Rendering happens before claiming; a template error can be repaired.
    deadline = [signup.confirmation_deadline, Time.current + (step == 1 ? 13.days : 7.days)].max
    signup.confirm_by = deadline
    delivery = SignupMailer.confirmation_reminder(signup, step)
    delivery.message
    claimed = product.reload.confirmation_reminder_due(step).where(id: signup.id)
      .update_all(columns.fetch(:checked) => Time.current, confirm_by: deadline)
    return unless claimed == 1

    signup.reload
    return if signup.confirmed? || signup.approved_at || !signup.product.reload.confirmation_reminders?

    begin
      delivery.deliver_now
      Signup.where(id: signup.id).update_all(columns.fetch(:sent) => Time.current)
    rescue StandardError
      Signup.where(id: signup.id).update_all(columns.fetch(:failed) => Time.current)
      raise
    end
  end
end
