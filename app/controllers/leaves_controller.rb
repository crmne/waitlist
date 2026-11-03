class LeavesController < PublicController
  def show
    @signup = Signup.find_by_token_for(:leave, params[:token])
    @product = @signup&.product
    render :gone unless @signup
  end

  # The page's button, or a mail provider's RFC 8058 one-click POST from
  # the List-Unsubscribe header (no session or CSRF token either way). Only
  # someone leaving by hand on the page gets the "you've left" email.
  def create
    signup = Signup.find_by_token_for(:leave, params[:token])
    @product = signup&.product
    if signup
      SignupMailer.left(signup.product, signup.email).deliver_later unless one_click?
      signup.forget!
    end
    render :gone
  end

  private

  def one_click? = params["List-Unsubscribe"] == "One-Click"
end
