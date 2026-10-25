# The too-fast half of invisible_captcha, without a session: a form that is
# sent less than InvisibleCaptcha.timestamp_threshold seconds after it was
# shown is a bot. The hosted form carries a signed start time (`started`);
# the example.com script sends how long its page was open (`elapsed_ms`).
module SpamCheck
  def self.started_token(now = Time.current) = verifier.generate(now.to_f, expires_in: 1.day, purpose: :form_started)

  def self.too_fast?(params, now: Time.current)
    threshold = InvisibleCaptcha.timestamp_threshold.to_f
    if params[:started].present?
      started = verifier.verified(params[:started].to_s, purpose: :form_started)
      started.nil? || now.to_f - started < threshold
    elsif params[:elapsed_ms].present?
      elapsed = Integer(params[:elapsed_ms].to_s, 10, exception: false)
      elapsed.nil? || elapsed < threshold * 1000
    else
      true
    end
  end

  def self.verifier = Rails.application.message_verifier(:waitlist_form_started)
end
