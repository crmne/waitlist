require "test_helper"

class ConfirmationReminderTest < ActiveSupport::TestCase
  class BrokenDelivery
    def initialize(*) = nil
    def deliver!(_mail) = raise(IOError, "SMTP connection lost")
  end

  setup do
    @product = acme
    @product.update!(settings: @product.settings.merge("confirmation_reminders" => true))
    @signup = @product.signups.create!(email: "dj@example.com", source: "site", consent_text: "original consent",
      created_at: 25.hours.ago, confirmation_sent_at: 25.hours.ago)
  end

  test "first reminder waits a full day and duplicate sweeps send only once" do
    travel_to Time.current.change(usec: 0) do
      @signup.update!(created_at: 1.day.ago + 1.second, confirmation_sent_at: 1.day.ago + 1.second)
      assert_no_enqueued_jobs(only: ConfirmationReminderJob) { ConfirmationRemindersJob.perform_now }
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup) }
      travel 1.second
      2.times { assert_enqueued_with(job: ConfirmationReminderJob, args: [@signup, 1]) { ConfirmationRemindersJob.perform_now } }
      assert_emails(1) { perform_enqueued_jobs(only: ConfirmationReminderJob) }
      assert @signup.reload.confirmation_reminder_sent_at
      assert_nil @signup.confirmation_reminder_failed_at
      assert_equal "original consent", @signup.consent_text
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup) }
    end
  end

  test "second reminder waits for day seven and six days after the first with no third" do
    travel_to Time.current.change(usec: 0) do
      @signup.update!(created_at: 1.day.ago, confirmation_sent_at: 1.day.ago)
      assert_emails(1) { ConfirmationReminderJob.perform_now(@signup) }
      travel 6.days - 1.second
      assert_no_enqueued_jobs(only: ConfirmationReminderJob) { ConfirmationRemindersJob.perform_now }
      travel 1.second
      assert_enqueued_with(job: ConfirmationReminderJob, args: [@signup, 2]) { ConfirmationRemindersJob.perform_now }
      assert_emails(1) { perform_enqueued_jobs(only: ConfirmationReminderJob) }
      mail = ActionMailer::Base.deliveries.last
      assert_equal "Still want to join the Acme waitlist?", mail.subject
      assert_includes mail.text_part.decoded, "last confirmation reminder"
      assert @signup.reload.confirmation_reminder_second_sent_at
      assert_no_emails { 2.times { ConfirmationReminderJob.perform_now(@signup, 2) } }
      travel 30.days
      assert_no_enqueued_jobs(only: ConfirmationReminderJob) { ConfirmationRemindersJob.perform_now }
    end
  end

  test "late first reminder preserves spacing and gives seven days after the final email" do
    travel_to Time.current.change(usec: 0) do
      @signup.update!(created_at: 10.days.ago, confirmation_sent_at: 10.days.ago, confirm_by: 4.days.from_now)
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup, 2) }
      assert_emails(1) { ConfirmationReminderJob.perform_now(@signup) }
      assert_equal 13.days.from_now, @signup.reload.confirm_by
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup, 2) }
      travel 6.days
      RetentionJob.perform_now
      assert Signup.exists?(@signup.id)
      # Simulate a further queue delay before the second delivery.
      travel 1.day
      assert_emails(1) { ConfirmationReminderJob.perform_now(@signup, 2) }
      assert_equal 7.days.from_now, @signup.reload.confirm_by
      assert_includes ActionMailer::Base.deliveries.last.text_part.decoded, @signup.confirm_by.strftime("%-d %B %Y")
      travel 7.days + 1.second
      RetentionJob.perform_now
      assert_not Signup.exists?(@signup.id)
    end
  end

  test "confirmation after enqueue and after the first reminder cancels remaining sends" do
    ConfirmationRemindersJob.perform_now
    @signup.confirm!
    assert_no_emails { perform_enqueued_jobs(only: ConfirmationReminderJob) }
    assert_nil @signup.reload.confirmation_reminder_checked_at
    @signup.update!(confirmed_at: nil)
    assert_emails(1) { ConfirmationReminderJob.perform_now(@signup) }
    travel 6.days do
      ConfirmationRemindersJob.perform_now
      @signup.confirm!
      assert_no_emails { perform_enqueued_jobs(only: ConfirmationReminderJob) }
    end
  end

  test "leaving after enqueue discards the job" do
    ConfirmationRemindersJob.perform_now
    @signup.forget!
    assert_no_emails { perform_enqueued_jobs(only: ConfirmationReminderJob) }
    assert Suppression.suppressed?(@product, "dj@example.com")
  end

  test "configuration can stop queued reminders without resetting consumed attempts" do
    ConfirmationRemindersJob.perform_now
    @product.update!(settings: @product.settings.merge("confirmation_reminders" => false))
    assert_no_emails { perform_enqueued_jobs(only: ConfirmationReminderJob) }
    @product.update!(settings: @product.settings.merge("confirmation_reminders" => true))
    assert_emails(1) { ConfirmationReminderJob.perform_now(@signup) }
    @product.update!(settings: @product.settings.except("confirmation_reminders"))
    @product.update!(settings: @product.settings.merge("confirmation_reminders" => true))
    assert_no_emails { ConfirmationReminderJob.perform_now(@signup) }
  end

  test "imported, already reminded, unmailed, approved and expired signups are excluded" do
    [
      { source: "getwaitlist" }, { reminder_sent_at: 2.days.ago },
      { confirmation_sent_at: nil }, { approved_at: Time.current },
      { confirm_by: Time.current }, { confirm_by: nil, created_at: 15.days.ago }
    ].each do |attributes|
      saved = @signup.attributes.slice(*attributes.keys.map(&:to_s))
      @signup.update!(attributes)
      assert_no_enqueued_jobs(only: ConfirmationReminderJob) { ConfirmationRemindersJob.perform_now }
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup) }
      @signup.update!(saved)
    end
    @signup.update!(source: "form")
    assert_emails(1) { ConfirmationReminderJob.perform_now(@signup) }
  end

  test "a requested resend postpones reminders without restarting the sequence" do
    travel_to Time.current.change(usec: 0)
    @signup.update!(confirmation_sent_at: Time.current)
    assert_no_emails { ConfirmationReminderJob.perform_now(@signup) }
    travel 1.day do
      assert_emails(1) { ConfirmationReminderJob.perform_now(@signup) }
    end
    travel 7.days do
      @signup.update!(confirmation_sent_at: Time.current)
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup, 2) }
      travel 1.day
      assert_emails(1) { ConfirmationReminderJob.perform_now(@signup, 2) }
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup) }
    end
  end

  test "overlapping jobs claim a single delivery and confirmation during rendering stops it" do
    original = SignupMailer.method(:confirmation_reminder)
    nested = false
    with_reminder_mailer(->(signup, step) {
      unless nested
        nested = true
        ConfirmationReminderJob.perform_now(Signup.find(signup.id), step)
      end
      original.call(signup, step)
    }) do
      assert_emails(1) { ConfirmationReminderJob.perform_now(@signup) }
    end
    travel 6.days do
      with_reminder_mailer(->(signup, step) {
        Signup.find(signup.id).confirm!
        original.call(signup, step)
      }) do
        assert_no_emails { ConfirmationReminderJob.perform_now(@signup, 2) }
      end
    end
  end

  test "an uncertain SMTP result is claimed and failed without a retry or second reminder" do
    original = SignupMailer.delivery_method
    SignupMailer.add_delivery_method :broken_confirmation, BrokenDelivery
    SignupMailer.delivery_method = :broken_confirmation
    assert_raises(IOError) { ConfirmationReminderJob.perform_now(@signup) }
    SignupMailer.delivery_method = original
    assert @signup.reload.confirmation_reminder_checked_at
    assert @signup.confirmation_reminder_failed_at
    assert_nil @signup.confirmation_reminder_sent_at
    assert_no_emails { ConfirmationReminderJob.perform_now(@signup) }
    travel 7.days do
      assert_no_emails { ConfirmationReminderJob.perform_now(@signup, 2) }
    end
  ensure
    SignupMailer.delivery_method = original
  end

  test "both reminders contain working confirmation and leave links in branded multipart mail" do
    [1, 2].each do |step|
      mail = SignupMailer.confirmation_reminder(@signup, step).message
      assert_equal "Acme <hello@acme.example>", mail[:from].value
      assert_equal ["team@acme.example"], mail.reply_to
      assert mail["List-Unsubscribe"]
      assert_includes mail.html_part.decoded, "/brands/acme/logo.png"
      assert_includes mail.html_part.decoded, "Acme GmbH"
      text = mail.text_part.decoded
      confirm = text[%r{https?://\S+/confirm/(\S+)}, 1]
      leave = text[%r{https?://\S+/leave/(\S+)}, 1]
      assert_equal @signup.id, Signup.find_by_token_for!(:confirmation, confirm).id
      assert_equal @signup.id, Signup.find_by_token_for!(:leave, leave).id
      assert_includes mail.html_part.decoded, confirm
      assert_includes mail.html_part.decoded, leave
    end
    assert_raises(ArgumentError) { ConfirmationReminderJob.perform_now(@signup, 3) }
  end

  test "enabled products retain recent existing signups for two weeks and respect explicit deadlines" do
    @signup.update!(created_at: 8.days.ago, confirm_by: nil)
    RetentionJob.perform_now
    assert Signup.exists?(@signup.id)
    @signup.update!(created_at: 15.days.ago)
    RetentionJob.perform_now
    assert_not Signup.exists?(@signup.id)
    imported = @product.signups.create!(email: "import@example.com", source: "getwaitlist", consent_text: "one reminder",
      created_at: 100.days.ago, confirm_by: 1.day.from_now, reminder_sent_at: 13.days.ago)
    RetentionJob.perform_now
    assert Signup.exists?(imported.id)
    travel 2.days do
      RetentionJob.perform_now
      assert_not Signup.exists?(imported.id)
    end
  end

  test "the setting is opt-in and consent distinguishes confirmation from activation" do
    assert_not Product.find_by!(slug: "plain").confirmation_reminders?
    assert_includes @product.consent_text, "two confirmation reminders after one day and one week"
    assert_in_delta @signup.created_at + 14.days, @signup.confirm_by, 1.second
    mail = SignupMailer.confirmation(@signup).message
    assert_includes mail.text_part.decoded, "after one day and one week"
    ["true", {}, 1].each do |value|
      @product.settings["confirmation_reminders"] = value
      assert_not @product.valid?
    end
  end

  def with_reminder_mailer(callable)
    SignupMailer.define_singleton_method(:confirmation_reminder, callable)
    yield
  ensure
    SignupMailer.singleton_class.remove_method(:confirmation_reminder)
  end
end
