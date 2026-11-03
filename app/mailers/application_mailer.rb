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
    # RFC 8058 one-click: the provider POSTs "List-Unsubscribe=One-Click"
    # to the leave link (LeavesController#create).
    if leave
      headers["List-Unsubscribe"] = "<#{leave}>"
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    end
    # SES publishes this message's bounce or complaint to the configuration
    # set's topic, tagged with the product (SesEvent). SES removes both
    # headers before delivery.
    if (configuration_set = Rails.configuration.x.ses_configuration_set)
      headers["X-SES-CONFIGURATION-SET"] = configuration_set
      headers["X-SES-MESSAGE-TAGS"] = "product=#{@product.slug}"
    end
    mail(to:, from: @product.from_address, reply_to: @product.reply_to, subject:, "Auto-Submitted" => "auto-generated", **headers)
  end
end
