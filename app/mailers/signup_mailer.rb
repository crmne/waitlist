class SignupMailer < ApplicationMailer
  def confirmation(signup)
    @signup = signup
    @product = signup.product
    @confirm_url = confirmation_url(token: signup.generate_token_for(:confirmation))
    @leave_url = leave_url(token: signup.generate_token_for(:leave))
    @referral_url = product_form_url(@product.slug, ref: signup.referral_code)
    headers["List-Unsubscribe"] = "<#{@leave_url}>"
    headers["Auto-Submitted"] = "auto-generated"
    mail to: signup.email, from: @product.from_address, reply_to: @product.reply_to,
      subject: "Confirm your place on the #{@product.name} waitlist"
  end
end
