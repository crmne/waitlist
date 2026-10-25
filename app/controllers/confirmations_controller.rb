class ConfirmationsController < PublicController
  def show
    @signup = Signup.find_by_token_for(:confirmation, params[:token])
    @product = @signup&.product
    render :expired, status: :not_found unless @signup
  end

  def create
    @signup = Signup.find_by_token_for(:confirmation, params[:token])
    return render(:expired, status: :not_found) unless @signup
    @product = @signup.product
    @signup.confirm!
    render :confirmed
  end
end
