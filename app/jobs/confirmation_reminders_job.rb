class ConfirmationRemindersJob < ApplicationJob
  def perform
    Product.find_each do |product|
      [1, 2].each do |step|
        product.confirmation_reminder_due(step).find_each do |signup|
          ConfirmationReminderJob.perform_later(signup, step)
        end
      end
    end
  end
end
