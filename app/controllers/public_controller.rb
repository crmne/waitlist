# Pages anyone can open. They set no cookie (no session, no CSRF token: each
# write is authorised by an unguessable token in its URL, or is a signup
# that does nothing until confirmed by email).
class PublicController < ApplicationController
  skip_forgery_protection
  before_action :no_cookies

  layout "public"

  private

  def no_cookies
    request.session_options[:skip] = true
  end
end
