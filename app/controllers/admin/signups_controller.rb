class Admin::SignupsController < Admin::BaseController
  before_action :find_signup

  def approve
    @signup.approve!
    redirect_to admin_product_path(@signup.product, status: "waiting"), notice: "Approved #{@signup.email}."
  rescue ArgumentError => error
    redirect_to admin_product_path(@signup.product), alert: error.message
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
