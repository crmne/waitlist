class OwnerMailer < ApplicationMailer
  def joined(signup)
    @signup = signup
    @product = signup.product
    @place = signup.place_in_line
    @waiting = @product.signups.waiting.count
    @admin_url = admin_product_url(@product, anchor: "signup-#{signup.id}")
    headers["Auto-Submitted"] = "auto-generated"
    mail to: @product.notify_address, from: @product.from_address,
      subject: "#{@product.name} waitlist: #{signup.email} joined#{" (##{@place})" if @place}"
  end
end
