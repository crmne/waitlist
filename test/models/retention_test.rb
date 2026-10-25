require "test_helper"

class RetentionTest < ActiveSupport::TestCase
  test "unconfirmed signups go after a week, approved ones after the product's keep period" do
    old_pending = acme.signups.create!(email: "old@example.com", consent_text: "t", created_at: 8.days.ago)
    new_pending = acme.signups.create!(email: "new@example.com", consent_text: "t", created_at: 1.day.ago)
    waiting = confirmed_signup("wait@example.com", at: 400.days.ago)
    approved_long_ago = confirmed_signup("done@example.com", at: 200.days.ago)
    approved_long_ago.update!(approved_at: 91.days.ago)

    RetentionJob.perform_now

    assert_not Signup.exists?(old_pending.id)
    assert Signup.exists?(new_pending.id)
    assert Signup.exists?(waiting.id)
    assert_not Signup.exists?(approved_long_ago.id)
  end

  test "places in line follow signup time among people still waiting" do
    a = confirmed_signup("a@example.com", at: 3.days.ago)
    b = confirmed_signup("b@example.com", at: 2.days.ago)
    c = confirmed_signup("c@example.com", at: 1.day.ago)
    assert_equal [1, 2, 3], [a, b, c].map(&:place_in_line)
    a.update!(approved_at: Time.current)
    assert_nil a.place_in_line
    assert_equal [1, 2], [b, c].map(&:place_in_line)
  end
end
