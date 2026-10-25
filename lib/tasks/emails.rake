namespace :emails do
  desc "Send one sample of each email of PRODUCT to TO, with fake data and [Sample] in the subject. KINDS=confirmation,reminder,approved,left,joined (default: all). APPROVAL_TEMPLATE=path (and APPROVAL_VARIABLES=json) use that template for 'approved' when the product has none."
  task :sample, [:product, :to] => :environment do |_, args|
    product = Product.find_by!(slug: args.fetch(:product))
    to = args.fetch(:to)
    if ENV["APPROVAL_TEMPLATE"].present? && product.approval_email_template.nil?
      variables = ENV["APPROVAL_VARIABLES"].present? ? JSON.parse(ENV["APPROVAL_VARIABLES"]) : product.approval_email_variables
      product.settings = product.settings.merge("approval_email" => { "template" => ENV["APPROVAL_TEMPLATE"], "variables" => variables })
    end
    answers = product.questions.to_h { |q| [q["question"], q["options"].first] }
    fake = ->(id, **attributes) { Signup.new(id:, product:, email: to, consent_text: "sample", referral_code: "SAMPLE#{id}", created_at: Time.current, answers:, **attributes) }
    kinds = (ENV["KINDS"].presence || "confirmation,reminder,approved,left,joined").split(",")
    mails = {
      "confirmation" => -> { SignupMailer.confirmation(fake.(900_001)) },
      "reminder" => -> { SignupMailer.reminder(fake.(900_002, confirm_by: product.reminder_days.days.from_now)) },
      "approved" => -> {
        variables = product.approval_email_variables.merge("key" => "SAMPLE-KEY-NOT-VALID", "expires_at" => 180.days.from_now.utc.iso8601)
        SignupMailer.approved(fake.(900_003, confirmed_at: Time.current), variables)
      },
      "left" => -> { SignupMailer.left(product, to) },
      "joined" => -> { OwnerMailer.joined(fake.(900_004, confirmed_at: Time.current)) }
    }
    kinds.each do |kind|
      message = mails.fetch(kind).call.message
      message.to = [to]
      message.subject = "[Sample] #{message.subject}"
      message.deliver
      puts "sent #{kind}"
    end
  end
end
