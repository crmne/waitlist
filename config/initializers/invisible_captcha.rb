# Chat with Work's waitlist used invisible_captcha with a 3-second
# timestamp. Its timestamp lives in the session (a cookie), which public
# pages here never set, so the gem checks only the honeypot and
# SpamCheck does the timing without a cookie.
InvisibleCaptcha.setup do |config|
  config.timestamp_enabled = false
  config.spinner_enabled = false
  config.timestamp_threshold = 3
  config.honeypots = ["website"]
end
