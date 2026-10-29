require "test_helper"

class ApprovalFollowUpTest < ActiveSupport::TestCase
  class BrokenDelivery
    def initialize(*) = nil
    def deliver!(_mail) = raise(IOError, "SMTP connection lost")
  end

  setup do
    @product = acme
    settings = @product.settings.deep_dup
    settings["on_approve"]["follow_up_url"] = "http://hooks.internal/follow-up"
    settings["approval_follow_up"] = {"steps" => [
      {"after_hours" => 24, "template" => "brands/acme/follow-up.md",
        "variables" => {"download_url" => "https://acme.example/download"}},
      {"after_hours" => 168, "template" => "brands/acme/follow-up-week.md",
        "variables" => {"download_url" => "https://acme.example/download"}}
    ]}
    @product.update!(settings: settings)
    @signup = confirmed_signup(product: @product)
    @signup.update!(approved_at: 3.days.ago, approval_emailed_at: 25.hours.ago)
    @requests = []
    decision(true)
  end

  def decision(value, code: "200", &block)
    ApprovalWebhook.transport = lambda do |uri, request|
      @requests << [uri.path, JSON.parse(request.body), request["Authorization"]]
      block&.call
      WebhookResponse.new(code, JSON.generate(send_follow_up: value))
    end
  end

  test "24 hours starts at the successful invitation email, not approval" do
    travel_to Time.current.change(usec: 0) do
      @signup.update!(approval_emailed_at: 24.hours.ago + 1.second)
      assert_no_enqueued_jobs(only: ApprovalFollowUpJob) { ApprovalFollowUpsJob.perform_now }
      assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
      assert_empty @requests
      travel 1.second
      assert_enqueued_with(job: ApprovalFollowUpJob, args: [@signup, 1]) { ApprovalFollowUpsJob.perform_now }
      assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup) }
    end
    assert_equal [["/follow-up", {"reference" => ApprovalWebhook.reference_for(@signup)}, "Bearer test-token"]], @requests
    assert @signup.reload.approval_follow_up_sent_at
    assert_nil @signup.approval_follow_up_failed_at
    email = ActionMailer::Base.deliveries.last
    assert_equal ["team@acme.example"], email.reply_to
    assert_includes email.text_part.decoded, "https://acme.example/download"
    assert_includes email.html_part.decoded, "https://acme.example/download"
    assert email["List-Unsubscribe"]
    assert_no_emails { 2.times { ApprovalFollowUpJob.perform_now(@signup) } }
    assert_no_enqueued_jobs(only: ApprovalFollowUpJob) { ApprovalFollowUpsJob.perform_now }
  end

  test "activation between enqueue and execution suppresses the message permanently" do
    ApprovalFollowUpsJob.perform_now
    decision(false)
    assert_no_emails { perform_enqueued_jobs(only: ApprovalFollowUpJob) }
    assert @signup.reload.approval_follow_up_checked_at
    assert_nil @signup.approval_follow_up_sent_at
    decision(true)
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
  end

  test "unconfirmed, unapproved, unsent, deleted and disabled products are skipped" do
    [:confirmed_at, :approved_at, :approval_emailed_at].each do |column|
      previous = @signup[column]
      @signup.update!(column => nil)
      assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
      @signup.update!(column => previous)
    end
    @product.update!(settings: @product.settings.except("approval_follow_up"))
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
    @signup.forget!
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
    assert_empty @requests
  end

  test "leaving or withdrawing approval during the status check prevents sending" do
    decision(true) { @signup.update!(approved_at: nil) }
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
    @signup.update!(approved_at: Time.current)
    decision(true) { @signup.forget! }
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
  end

  test "malformed and failed status replies send nothing and keep the attempt available" do
    [nil, "true", 1].each do |value|
      decision(value)
      assert_no_emails { assert_raises(ApprovalWebhook::Error) { ApprovalFollowUpJob.new.perform(@signup) } }
      assert_nil @signup.reload.approval_follow_up_checked_at
    end
    decision(true, code: "503")
    assert_no_emails { assert_raises(ApprovalWebhook::Error) { ApprovalFollowUpJob.new.perform(@signup) } }
    decision(true)
    assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup) }
  end

  test "overlapping jobs can claim only one delivery" do
    nested = false
    decision(true) do
      unless nested
        nested = true
        ApprovalFollowUpJob.perform_now(Signup.find(@signup.id))
      end
    end
    assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup) }
  end

  test "an uncertain SMTP result is recorded and never automatically retried" do
    original = SignupMailer.delivery_method
    SignupMailer.add_delivery_method :broken, BrokenDelivery
    SignupMailer.delivery_method = :broken
    assert_raises(IOError) { ApprovalFollowUpJob.perform_now(@signup) }
    SignupMailer.delivery_method = original
    assert @signup.reload.approval_follow_up_checked_at
    assert @signup.approval_follow_up_failed_at
    assert_nil @signup.approval_follow_up_sent_at
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup) }
  ensure
    SignupMailer.delivery_method = original
  end

  test "follow-up configuration is optional and validates timing and integration" do
    assert_nil Product.find_by!(slug: "plain").approval_follow_up
    [0, -1, 169, "24", nil].each do |hours|
      @product.settings["approval_follow_up"]["steps"][0]["after_hours"] = hours
      refute @product.valid?
    end
    @product.settings["approval_follow_up"]["steps"][0]["after_hours"] = 24
    @product.settings["on_approve"].delete("follow_up_url")
    refute @product.valid?
  end

  test "second reminder follows the first after six days, with distinct copy and no third" do
    travel_to Time.current.change(usec: 0) do
      @signup.update!(approval_emailed_at: 24.hours.ago)
      assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup, 1) }
      assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
      travel 6.days - 1.second
      assert_no_enqueued_jobs(only: ApprovalFollowUpJob) { ApprovalFollowUpsJob.perform_now }
      travel 1.second
      assert_enqueued_with(job: ApprovalFollowUpJob, args: [@signup, 2]) { ApprovalFollowUpsJob.perform_now }
      assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup, 2) }
      assert_equal "Anything holding you back?", ActionMailer::Base.deliveries.last.subject
      assert @signup.reload.approval_follow_up_second_sent_at
      assert_no_emails { 2.times { ApprovalFollowUpJob.perform_now(@signup, 2) } }
      travel 30.days
      assert_no_enqueued_jobs(only: ApprovalFollowUpJob) { ApprovalFollowUpsJob.perform_now }
    end
  end

  test "old invitations never receive both reminders together" do
    travel_to Time.current.change(usec: 0) do
      @signup.update!(approval_emailed_at: 20.days.ago)
      assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
      assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup, 1) }
      assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
      travel 6.days - 1.second
      assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
      travel 1.second
      assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup, 2) }
    end
  end

  test "activation after the first reminder cancels the second permanently" do
    assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup, 1) }
    travel 7.days do
      ApprovalFollowUpsJob.perform_now
      decision(false)
      assert_no_emails { perform_enqueued_jobs(only: ApprovalFollowUpJob) }
      assert @signup.reload.approval_follow_up_second_checked_at
      assert_nil @signup.approval_follow_up_second_sent_at
      decision(true)
      assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
    end
  end

  test "a suppressed or uncertain first reminder prevents the second" do
    @signup.update!(approval_emailed_at: 20.days.ago)
    decision(false)
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 1) }
    decision(true)
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
    @signup.update!(approval_follow_up_failed_at: Time.current)
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
    assert_nil @signup.reload.approval_follow_up_second_checked_at
  end

  test "duplicate jobs can only send the second reminder once" do
    @signup.update!(approval_emailed_at: 20.days.ago, approval_follow_up_sent_at: 7.days.ago)
    nested = false
    decision(true) do
      unless nested
        nested = true
        ApprovalFollowUpJob.perform_now(Signup.find(@signup.id), 2)
      end
    end
    assert_emails(1) { ApprovalFollowUpJob.perform_now(@signup, 2) }
  end

  test "disabling a step during its check suppresses delivery" do
    @signup.update!(approval_emailed_at: 20.days.ago, approval_follow_up_sent_at: 7.days.ago)
    decision(true) do
      settings = @product.settings.deep_dup
      settings["approval_follow_up"]["steps"].pop
      @product.update!(settings:)
    end
    assert_no_emails { ApprovalFollowUpJob.perform_now(@signup, 2) }
    assert_nil @signup.reload.approval_follow_up_second_checked_at
  end

  test "configuration allows at most two ordered steps and consent reflects the count" do
    assert_includes @product.consent_text, "up to two"
    steps = @product.settings["approval_follow_up"]["steps"].deep_dup
    [[], [steps.first] * 3, steps.reverse, [steps.first, steps.first], [nil], "invalid"].each do |invalid|
      @product.settings["approval_follow_up"]["steps"] = invalid
      refute @product.valid?
    end
    @product.settings["approval_follow_up"]["steps"] = [steps.first]
    assert @product.valid?
    assert_includes @product.consent_text, "one getting-started"
    assert_nil @product.approval_follow_up_step(0)
    assert_nil @product.approval_follow_up_step(3)
  end
end
