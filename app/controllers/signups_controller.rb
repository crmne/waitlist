class SignupsController < PublicController
  before_action :find_product
  # Before anything that may answer early (rate limit, spam), so those
  # answers reach the product's own pages too.
  before_action :allow_cross_origin, only: %i[create preflight]
  after_action :allow_framing, only: %i[new thanks]

  # Per address, in memory only: the bucket is an HMAC of the address with a
  # per-process key (client_bucket), nothing is logged, and it is gone after
  # ten minutes or a restart.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)
  rate_limit to: 10, within: 10.minutes, by: -> { client_bucket }, only: :create, store: RATE_LIMIT_STORE,
    with: -> { respond_with_error("Too many attempts. Please wait a few minutes and try again.", :too_many_requests) }

  # Spam is answered as if it worked, with nothing stored or emailed, as
  # invisible_captcha does: the honeypot (the gem) and a form sent too fast
  # (SpamCheck, the gem's timestamp without its session cookie).
  invisible_captcha only: :create, honeypot: :website, timestamp_enabled: false, on_spam: :respond_with_success
  before_action :refuse_too_fast, only: :create

  def new
    @embedded = params[:embed].present?
    @referral = referral_param
  end

  def create
    email = Signup.normalize_value_for(:email, params[:email])
    signup = @product.signups.find_or_initialize_by(email:)
    if signup.new_record?
      signup.assign_attributes(answers: @product.clean_answers(params[:answers]), consent_text: Signup::CONSENT_TEXT, source: "form")
      return respond_with_error("Please enter a valid email address.") unless signup.valid?
      return respond_with_error("Please check your email address: #{email.split("@").last} doesn't seem to receive email.") unless EmailDomain.deliverable?(email)
      signup.referred_by = Signup.referrer_for(@product, referral_param, email)
      signup.save!
    elsif !signup.confirmed? && params[:answers].present?
      signup.update!(answers: @product.clean_answers(params[:answers]))
    end

    # The same answer whether or not the address was already here, so the
    # form can't be used to find out who signed up.
    if signup.can_send_confirmation?
      signup.update!(confirmation_sent_at: Time.current)
      SignupMailer.confirmation(signup).deliver_later
    end
    respond_with_success
  rescue ActiveRecord::RecordNotUnique
    respond_with_success
  end

  def preflight = head(:no_content)

  def thanks
    @embedded = params[:embed].present?
  end

  private

  def referral_param = (params[:ref].presence || params[:ref_id].presence)&.to_s&.first(64)

  def refuse_too_fast
    respond_with_success if SpamCheck.too_fast?(params)
  end

  # invisible_captcha's spam warning names the client address; nothing here
  # logs one.
  def warn_spam(_message) = nil

  def respond_with_success
    respond_to do |format|
      format.json { render json: { status: "check_email" }, status: :accepted }
      format.any { redirect_to(@product.thanks_url.presence || product_thanks_path(@product.slug, embed: params[:embed].presence), allow_other_host: true, status: :see_other) }
    end
  end

  def respond_with_error(message, status = :unprocessable_content)
    respond_to do |format|
      format.json { render json: { status: "error", message: }, status: }
      format.any do
        @error = message
        @embedded = params[:embed].present?
        @referral = referral_param
        render :new, status:, formats: :html
      end
    end
  end

  def allow_cross_origin
    origin = request.headers["Origin"]
    return unless @product.allows_origin?(origin)
    response.headers["Access-Control-Allow-Origin"] = origin
    response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Accept"
    response.headers["Access-Control-Max-Age"] = "86400"
    response.headers["Vary"] = "Origin"
  end

  # The hosted form may sit in an iframe on the product's own sites only.
  def allow_framing
    response.headers.delete("X-Frame-Options")
    form_targets = ["'self'", origin_of(@product.thanks_url)].compact.join(" ")
    ancestors = ["'self'", *@product.allowed_origins].join(" ")
    response.headers["Content-Security-Policy"] =
      "default-src 'self'; style-src 'self'; img-src 'self' data:; form-action #{form_targets}; frame-ancestors #{ancestors}"
  end

  def origin_of(url)
    return if url.blank?
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}"
  end
end
