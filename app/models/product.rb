class Product < ApplicationRecord
  # The products file: config/products.yml (an example) unless PRODUCTS_FILE
  # names another, such as a deployment's own. Paths inside it (logo,
  # templates, token files) are relative to the file's folder.
  def self.config_path = Pathname(ENV.fetch("PRODUCTS_FILE", Rails.root.join("config/products.yml").to_s))

  SLUG = /\A[a-z0-9][a-z0-9-]{0,40}\z/
  DEFAULT_BRAND = {
    "background" => "#f6f5f2", "card" => "#ffffff", "text" => "#1b1b1d", "muted" => "#5d5a55",
    "accent" => "#1b1b1d", "accent_text" => "#ffffff", "line" => "#e4e1db",
    "font" => "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
    "heading_font" => nil, "font_css_url" => nil, "dir" => nil, "logo" => nil, "logo_width" => 120, "logo_height" => nil, "impressum" => nil
  }.freeze

  has_many :signups, dependent: :destroy
  has_many :suppressions, dependent: :delete_all

  validates :slug, format: SLUG, uniqueness: true
  validates :name, :site_url, :privacy_url, :from_address, presence: true
  validates :keep_approved_days, numericality: { only_integer: true, greater_than: 0 }
  validates :places_per_referral, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :valid_approval_follow_up
  validate :valid_confirmation_reminders

  # Creates or updates every product in the products file. Never deletes:
  # a product left out of the file keeps its row and its signups.
  def self.sync!(path = config_path)
    path = Pathname(path)
    config = YAML.safe_load_file(path) || {}
    transaction do
      config.each do |slug, attributes|
        product = find_or_initialize_by(slug:)
        product.update!(
          name: attributes.fetch("name"),
          site_url: attributes.fetch("site_url"),
          privacy_url: attributes.fetch("privacy_url"),
          from_address: attributes.fetch("from"),
          reply_to: attributes["reply_to"],
          notify_address: attributes["notify"].presence,
          allowed_origins: Array(attributes["allowed_origins"]),
          thanks_url: attributes["thanks_url"],
          keep_approved_days: attributes.fetch("keep_approved_days", 90),
          places_per_referral: attributes.fetch("places_per_referral", 5),
          questions: Array(attributes["questions"]).map { |q| { "question" => q.fetch("question"), "options" => Array(q.fetch("options")) } },
          settings: {
            "root" => path.dirname.to_s,
            "brand" => attributes["brand"] || {},
            "on_approve" => attributes["on_approve"],
            "approval_email" => attributes["approval_email"],
            "approval_follow_up" => attributes["approval_follow_up"],
            "confirmation_reminders" => attributes["confirmation_reminders"],
            "reminder_days" => attributes.fetch("reminder_days", 14),
            "analytics" => attributes["analytics"],
            "signup_experiments" => attributes["signup_experiments"]
          }.compact
        )
      end
    end
  end

  def to_param = slug

  # Everyone waiting, in order. Each starts at their place by signup time and
  # moves up `places_per_referral` places (passes that many people) for every
  # confirmed referral: on a tie, more referrals go first, then whoever signed
  # up first. Waitlists are small, so this is computed in Ruby.
  def line
    signups.waiting.in_line.to_a.each_with_index
      .sort_by { |signup, index| [index - places_per_referral * signup.effective_referrals, -signup.effective_referrals, index] }
      .map(&:first)
  end

  def allows_origin?(origin) = origin.present? && allowed_origins.include?(origin)

  def question_titles = questions.map { |q| q["question"] }

  # Keeps only answers to this product's questions that are one of its
  # options, comparing without surrounding spaces. Everything else is dropped.
  def clean_answers(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return {} unless raw.is_a?(Hash)

    questions.each_with_object({}) do |q, answers|
      value = raw[q["question"]].to_s.strip
      option = q["options"].find { |o| o.strip == value }
      answers[q["question"]] = option if option
    end
  end

  def brand = DEFAULT_BRAND.merge(settings.fetch("brand", {}).compact)

  def signup_experiments = settings.fetch("signup_experiments", {})

  # Store only a configured pair of fixed labels, never arbitrary query text.
  def clean_experiment(experiment, variant)
    return {} unless experiment.is_a?(String) && variant.is_a?(String)
    definition = signup_experiments[experiment]
    return {} unless definition && Array(definition["variants"]).include?(variant)
    return {} if experiment.length > 64 || variant.length > 64
    { experiment:, variant: }
  end

  # Counts actual records, independent of analytics delivery and the admin's
  # people-list filter. Earlier, missing and preview assignments stay unknown.
  def signup_experiment_reports
    signup_experiments.map do |name, definition|
      since = Time.iso8601(definition.fetch("started_at"))
      ended_at = Time.iso8601(definition["ended_at"]) if definition["ended_at"]
      cohort = signups.where(created_at: since..).where(experiment: [name, nil])
      cohort = cohort.where("created_at < ?", ended_at) if ended_at
      counts = cohort.group(:variant).pluck(:variant, Arel.sql("COUNT(*)"),
        Arel.sql("SUM(confirmed_at IS NOT NULL)")).to_h { |variant, total, confirmed| [variant, [total, confirmed]] }
      { name:, since:, ended_at:, rows: [*definition.fetch("variants"), nil].map { |variant|
        total, confirmed = counts.fetch(variant, [0, 0])
        { variant: variant || "Unattributed", total:, confirmed:, pending: total - confirmed }
      } }
    end
  end

  # Optional cookieless counting with Plausible: the product's script and the
  # address its events are reported under (page_url), so the page's own
  # address, which may carry a token, never leaves. Nil when not set up.
  def analytics
    a = settings["analytics"]
    return unless a.is_a?(Hash) && a["plausible_script"].to_s.start_with?("https://") && a["page_url"].to_s.start_with?("https://")
    a.slice("plausible_script", "page_url")
  end

  def analytics_origin
    uri = URI.parse(analytics["plausible_script"]) if analytics
    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}" if uri
  end

  # The sender's display name, for the footer and headings.
  def sender_name = Mail::Address.new(from_address).display_name.presence || name

  BRAND_FILE = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.(png|jpe?g|gif|css|woff2|txt)\z/

  # A file in the brand's folder (brand.dir), or nil.
  def brand_file(name)
    dir = brand["dir"].presence or return
    return unless name.to_s.match?(BRAND_FILE)
    path = resolve(dir).join(name.to_s)
    path if path.file? && path.dirname == resolve(dir)
  end

  def logo_path = brand["logo"].presence && brand_file(brand["logo"])

  def reminder_days = settings.fetch("reminder_days", 14).to_i

  # The approval webhook (ApprovalWebhook), or nil when approving only
  # records the decision.
  def on_approve = settings["on_approve"].presence

  def approval_email_template
    path = settings.dig("approval_email", "template").presence or return
    resolve(path).read
  end

  # Extra variables for the approval email, from the products file.
  def approval_email_variables = settings.dig("approval_email", "variables") || {}

  # Opt-in per product, with a fresh decision from its own service.
  def approval_follow_up = settings["approval_follow_up"].presence

  def consent_text
    if confirmation_reminders?
      text = "I agree to receive an email to confirm my address, up to two confirmation reminders after one day and one week, " \
        "and an invitation when there is a place."
      if approval_follow_up
        count = approval_follow_up.fetch("steps").size == 1 ? "one getting-started follow-up" : "up to two getting-started follow-ups"
        text += " I may also receive #{count} if needed after my invitation."
      end
      return text + " I can leave the list at any time."
    end
    return Signup::CONSENT_TEXT unless approval_follow_up
    follow_ups = approval_follow_up.fetch("steps").size == 1 ? "one getting-started follow-up" : "up to two getting-started follow-ups"
    "I agree to receive an email to confirm my address, an invitation when there is a place, " \
      "and #{follow_ups} if needed. I can leave the list at any time."
  end

  def confirmation_reminders? = settings["confirmation_reminders"] == true

  def unconfirmed_retention = confirmation_reminders? ? 14.days : Rails.configuration.x.unconfirmed_retention

  def confirmation_reminder_due(step = 1, now: Time.current)
    columns = Signup.confirmation_reminder_columns(step)
    return signups.none unless confirmation_reminders?

    due = signups.unconfirmed.where(source: %w[site form], approved_at: nil, reminder_sent_at: nil, columns.fetch(:checked) => nil)
      .where("created_at <= ?", now - Signup::CONFIRMATION_REMINDER_DELAYS.fetch(step - 1))
      .where("confirmation_sent_at <= ?", now - 1.day)
      .where("confirm_by > :now OR (confirm_by IS NULL AND created_at > :cutoff)", now:, cutoff: now - unconfirmed_retention)
    # A late first reminder never causes both steps to arrive together.
    due = due.where("confirmation_reminder_sent_at <= ?", now - 6.days) if step == 2
    due
  end

  def approval_follow_up_step(step)
    return unless [1, 2].include?(step)
    approval_follow_up&.fetch("steps")&.[](step - 1)
  end

  def approval_follow_up_template(step) = resolve(approval_follow_up_step(step).fetch("template")).read

  def approval_follow_up_variables(step) = approval_follow_up_step(step).fetch("variables", {})

  def approval_follow_up_due(step = 1)
    config = approval_follow_up_step(step) or return signups.none
    hours = config.fetch("after_hours")
    due = signups.confirmed.approved.where(Signup.follow_up_columns(step).fetch(:checked) => nil)
      .where("approval_emailed_at <= ?", hours.hours.ago)
    # Preserve the interval even when an older invitation's first reminder
    # goes out late. A suppressed or uncertain first send ends the sequence.
    if step == 2
      gap = hours - approval_follow_up_step(1).fetch("after_hours")
      due = due.where("approval_follow_up_sent_at <= ?", gap.hours.ago)
    end
    due
  end

  # What the admin calls the approval step's states.
  def approval_label(state)
    defaults = { "sent" => "Approval email sent", "failed" => "Approved, email failed",
      "registered" => "Approved, waiting to be sent", "pending" => "Approval not registered yet" }
    settings.dig("on_approve", "labels", state).presence || defaults.fetch(state)
  end

  def resolve(path)
    full = Pathname(path).absolute? ? Pathname(path) : Pathname(settings.fetch("root", Rails.root.to_s)).join(path)
    full.expand_path
  end

  private

  def valid_confirmation_reminders
    value = settings["confirmation_reminders"]
    errors.add(:settings, "confirmation_reminders must be true or false") unless [nil, true, false].include?(value)
  end

  def valid_approval_follow_up
    config = approval_follow_up or return
    steps = config["steps"] if config.is_a?(Hash)
    valid = steps.is_a?(Array) && (1..2).cover?(steps.size) && on_approve&.dig("follow_up_url").present?
    valid &&= steps.all? { |step| step.is_a?(Hash) && step["after_hours"].is_a?(Integer) &&
      (1..168).cover?(step["after_hours"]) && step["template"].is_a?(String) &&
      step["template"].present? && step.fetch("variables", {}).is_a?(Hash) }
    valid &&= steps.each_cons(2).all? { |first, second| first["after_hours"] < second["after_hours"] }
    unless valid
      errors.add(:settings, "approval_follow_up needs one or two ordered steps with after_hours (1..168), template, variables and on_approve.follow_up_url")
    end
  end
end
