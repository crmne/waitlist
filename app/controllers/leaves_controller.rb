class LeavesController < PublicController
  def show
    @signup = Signup.find_by_token_for(:leave, params[:token])
    @product = @signup&.product
    render :gone unless @signup
  end

  def create
    signup = Signup.find_by_token_for(:leave, params[:token])
    @product = signup&.product
    signup&.forget!
    render :gone
  end
end
