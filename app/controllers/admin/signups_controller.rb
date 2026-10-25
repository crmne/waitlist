class Admin::SignupsController < Admin::BaseController
  before_action :find_signup

  def approve
    @signup.approve!
    redirect_to admin_product_path(@signup.product, status: "waiting"), notice: "Approved #{@signup.email}."
  rescue ArgumentError => error
    redirect_to admin_product_path(@signup.product), alert: error.message
  end

  # Runs the approval step again where it stopped (webhook unreachable, no
  # token yet, or the approval email failed).
  def retry_approval
    ApprovalJob.perform_later(@signup) if @signup.approval_retryable?
    redirect_to admin_product_path(@signup.product, status: "approved"), notice: "Trying #{@signup.email}'s approval again."
  end

  def confirm_delete; end

  def destroy
    product = @signup.product
    @signup.forget!
    redirect_to admin_product_path(product), notice: "Deleted #{@signup.email}."
  end

  private

  def find_signup = @signup = Signup.find(params[:id])
end
