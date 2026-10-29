class SignupMailer < ApplicationMailer
  # Double opt-in, after someone signs up through a form.
  def confirmation(signup)
    prepare(signup)
    @validity_days = Rails.configuration.x.unconfirmed_retention.in_days.to_i
    branded_mail to: signup.email, subject: "Confirm your place on the #{@product.name} waitlist", leave: @leave
  end

  # The one email to someone imported unconfirmed: they asked to join on the
  # product's site and must confirm by confirm_by to keep their place.
  def reminder(signup)
    prepare(signup)
    @confirm_by = signup.confirm_by
    branded_mail to: signup.email, subject: "Please confirm your place on the #{@product.name} waitlist", leave: @leave
  end

  # The approval email, from the product's template and the approval
  # webhook's answer (ApprovalJob). The variables are never stored.
  def approved(signup, variables)
    prepare(signup)
    @template = TemplateText.new(@product.approval_email_template, variables.merge("email" => signup.email, "product" => @product.name))
    branded_mail to: signup.email, subject: @template.subject
  end

  def approval_follow_up(signup, step = 1)
    prepare(signup)
    @template = TemplateText.new(@product.approval_follow_up_template(step),
      @product.approval_follow_up_variables(step).merge("email" => signup.email, "product" => @product.name))
    branded_mail to: signup.email, subject: @template.subject, leave: @leave
  end

  # Confirms that someone who left is deleted. Takes the address, not the
  # signup, which is already gone.
  def left(product, email)
    @product = product
    branded_mail to: email, subject: "You've left the #{product.name} waitlist"
  end

  private

  def prepare(signup)
    @signup = signup
    @product = signup.product
    @confirm_url = confirmation_url(token: signup.generate_token_for(:confirmation)) unless signup.confirmed?
    @leave = leave_url(token: signup.generate_token_for(:leave))
    @referral_url = product_form_url(@product.slug, ref: signup.referral_code) if signup.referral_code
  end
end
