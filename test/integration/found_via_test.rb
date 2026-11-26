require "test_helper"
require "csv"

# "How did you find us?": a choice question, a short text question asked only
# after one of its answers, and the fixed class of page a site's form says
# someone came from.
class FoundViaTest < ActionDispatch::IntegrationTest
  FOUND = "How did you find us?"
  ASKED = "What did you ask it?"

  def join(email = "dj@example.com", **params)
    post "/p/acme/signups", params: { email:, elapsed_ms: 5000, **params }, as: :json
    assert_response :accepted
    acme.signups.find_by!(email:)
  end

  test "a text answer is kept on one line, cut to its length, after its question's answer" do
    signup = join(answers: { FOUND => "An AI assistant", ASKED => "  rekordbox\nalternative‮ for\tlinux with a very long tail of words  " })
    assert_equal "rekordbox alternative for linux with a v", signup.answers[ASKED]
    assert_equal 40, signup.answers[ASKED].length
    assert_equal "An AI assistant", signup.answers[FOUND]
  end

  test "a text answer is dropped when its question's answer was not given" do
    assert_equal({ FOUND => "Search" }, join("a@example.com", answers: { FOUND => "Search", ASKED => "something" }).answers)
    assert_equal({}, join("b@example.com", answers: { ASKED => "something" }).answers)
    assert_equal({ FOUND => "An AI assistant" }, join("c@example.com", answers: { FOUND => "An AI assistant", ASKED => " \n " }).answers)
    assert_equal({ FOUND => "An AI assistant" }, join("d@example.com", answers: { FOUND => "An AI assistant", ASKED => { "x" => "y" } }).answers)
  end

  test "a listed referrer class is saved once and anything else is dropped" do
    signup = join(referrer: "chatgpt")
    assert_equal "chatgpt", signup.referrer
    join(referrer: "claude")
    assert_equal "chatgpt", signup.reload.referrer

    ["https://chatgpt.com/c/123", "unknown", ["chatgpt"], { "a" => "b" }, "x" * 65].each_with_index do |referrer, index|
      assert_nil join("r#{index}@example.com", referrer:).referrer
    end
    post "/p/plain/signups", params: { email: "dj@example.com", elapsed_ms: 5000, referrer: "chatgpt" }, as: :json
    assert_nil Product.find_by!(slug: "plain").signups.sole.referrer
  end

  test "the admin counts answers and classes, and shows and exports each person's" do
    join("a@example.com", referrer: "chatgpt", answers: { FOUND => "An AI assistant", ASKED => "=HYPERLINK(1)" })
    join("b@example.com", referrer: "search", answers: { FOUND => "Search" })
    join("c@example.com")

    report = acme.answer_reports.to_h { [it[:title], it[:rows].to_h] }
    assert_equal({ "An AI assistant" => 1, "Search" => 1, "A friend" => 0, "No answer" => 1 }, report[FOUND])
    assert_equal({ "chatgpt" => 1, "claude" => 0, "search" => 1, "direct" => 0, "Not recorded" => 1 }, report["Came from"])
    assert_not report.key?(ASKED)

    get "/admin/products/acme?status=unconfirmed", headers: admin_headers
    assert_response :success
    assert_select ".answer-report table", 5 + 1
    assert_select "tr#signup-#{acme.signups.find_by!(email: "a@example.com").id} td", text: "=HYPERLINK(1)"
    assert_select "th", text: "Came from"

    get "/admin/products/acme/export", headers: admin_headers
    header, *rows = CSV.parse(response.body)
    row = rows.find { it.first == "a@example.com" }
    assert_equal "chatgpt", row[header.index("referrer")]
    assert_equal "'=HYPERLINK(1)", row[header.index(ASKED)]
  end

  test "the hosted form asks the text question as a text field and names its condition" do
    get "/p/acme"
    assert_select "input[type=text][maxlength='40'][name=?]", "answers[#{ASKED}]"
    assert_select "label .hint", text: "(if you chose “An AI assistant”)"
  end

  test "products with a misconfigured text question are refused" do
    product = acme
    product.questions = [{ "question" => "Asked?", "type" => "text", "only_if" => { "question" => "Nope", "answer" => "x" } }]
    assert_not product.valid?
    product.questions = [{ "question" => "Asked?", "type" => "text", "max_length" => 0 }]
    assert_not product.valid?
    product.questions = [{ "question" => "Kind?", "type" => "rating" }]
    assert_not product.valid?
    product.questions = [{ "question" => "Found?", "type" => "choice", "options" => ["AI"] },
      { "question" => "Asked?", "type" => "text", "only_if" => { "question" => "Found?", "answer" => "AI" } }]
    assert product.valid?
  end
end
