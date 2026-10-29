# The sweep also catches invitations sent before this feature was enabled.
class ApprovalFollowUpsJob < ApplicationJob
  def perform
    Product.find_each do |product|
      next unless product.approval_follow_up
      product.approval_follow_up.fetch("steps").each_index do |index|
        step = index + 1
        product.approval_follow_up_due(step).find_each do |signup|
          ApprovalFollowUpJob.perform_later(signup, step)
        end
      end
    end
  end
end
