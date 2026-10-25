class Product < ApplicationRecord
  CONFIG = Rails.root.join("config/products.yml")
  SLUG = /\A[a-z0-9][a-z0-9-]{0,40}\z/

  has_many :signups, dependent: :destroy
  has_many :suppressions, dependent: :delete_all

  validates :slug, format: SLUG, uniqueness: true
  validates :name, :site_url, :privacy_url, :from_address, presence: true
  validates :approval, inclusion: { in: LicenceIssuers::NAMES }, allow_nil: true
  validates :keep_approved_days, numericality: { only_integer: true, greater_than: 0 }

  # Creates or updates every product in config/products.yml. Never deletes:
  # a product left out of the file keeps its row and its signups.
  def self.sync!(path = CONFIG)
    config = YAML.safe_load_file(path) || {}
    transaction do
      config.each do |slug, attributes|
        product = find_or_initialize_by(slug:)
        product.update!(
          name: attributes.fetch("name"),
          site_url: attributes.fetch("site_url"),
          privacy_url: attributes.fetch("privacy_url"),
          from_address: attributes.fetch("from"),
          reply_to: attributes["reply_to"],
          allowed_origins: Array(attributes["allowed_origins"]),
          thanks_url: attributes["thanks_url"],
          approval: attributes["approval"],
          keep_approved_days: attributes.fetch("keep_approved_days", 90),
          questions: Array(attributes["questions"]).map { |q| { "question" => q.fetch("question"), "options" => Array(q.fetch("options")) } }
        )
      end
    end
  end

  def to_param = slug

  def allows_origin?(origin) = origin.present? && allowed_origins.include?(origin)

  def question_titles = questions.map { |q| q["question"] }

  # Keeps only answers to this product's questions that are one of its
  # options, comparing without surrounding spaces. Everything else is dropped.
  def clean_answers(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return {} unless raw.is_a?(Hash)

    questions.each_with_object({}) do |q, answers|
      value = raw[q["question"]].to_s.strip
      option = q["options"].find { |o| o.strip == value }
      answers[q["question"]] = option if option
    end
  end

  def licence_issuer = approval && LicenceIssuers.for(approval)
end
