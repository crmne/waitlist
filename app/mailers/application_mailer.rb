# Every email is branded by its product (Product#brand): logo, colours and
# fonts, the sender's name, and a footer with the product's Impressum line,
# privacy link and, for someone on the list, their leave link.
class ApplicationMailer < ActionMailer::Base
  layout "mailer"
  helper_method :brand

  private

  def brand = @product.brand

  def branded_mail(to:, subject:, leave: nil, **headers)
    @leave_url = leave
    @logo_url = brand_file_url(@product.slug, @product.brand["logo"]) if @product.logo_path
    headers["List-Unsubscribe"] = "<#{leave}>" if leave
    mail(to:, from: @product.from_address, reply_to: @product.reply_to, subject:, "Auto-Submitted" => "auto-generated", **headers)
  end
end
