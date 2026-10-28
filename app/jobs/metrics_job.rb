# Sends the waitlist's counts to our Seq (MetricsReport), every ten minutes
# (config/recurring.yml). Without an endpoint and key it does nothing. A
# send that fails is dropped: the next one carries the same counts.
class MetricsJob < ApplicationJob
  def perform
    MetricsReport.new.deliver if MetricsReport.enabled?
  end
end
