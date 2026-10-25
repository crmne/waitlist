class Admin::SignupsController < Admin::BaseController
  before_action :find_signup

  def approve
    @signup.approve!
    redirect_to admin_product_path(@signup.product, status: "waiting"), notice: "Approved #{@signup.email}."
  rescue ArgumentError => error
    redirect_to admin_product_path(@signup.product), alert: error.message
  end

  # Runs the approval step again for someone approved whose key wasn't
  # registered (licence-server unreachable, or no token yet).
  def register_licence
    ApprovalJob.perform_later(@signup) if @signup.approved_at && @signup.licence_issued_at.nil?
    redirect_to admin_product_path(@signup.product, status: "approved"), notice: "Registering a key for #{@signup.email} again."
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
