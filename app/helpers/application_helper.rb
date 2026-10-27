module ApplicationHelper
  # Names a public page for the product's analytics (the layout reports it as
  # PAGE_URL/NAME), with the events it counts: [name, props] pairs.
  def count_page(name, events = [])
    content_for :analytics, name
    @analytics_events = events
  end
end
