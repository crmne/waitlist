require "csv"

class Admin::ProductsController < Admin::BaseController
  STATUSES = %w[waiting unconfirmed approved].freeze

  def index
    @products = Product.order(:name)
    @counts = Signup.group(:product_id).pluck(
      :product_id,
      Arel.sql("SUM(confirmed_at IS NULL)"),
      Arel.sql("SUM(confirmed_at IS NOT NULL AND approved_at IS NULL)"),
      Arel.sql("SUM(approved_at IS NOT NULL)"),
      Arel.sql("SUM(approved_at IS NOT NULL AND approval_emailed_at IS NULL AND (approval_registered_at IS NULL OR approval_failed_at IS NOT NULL))")
    ).to_h { |id, *counts| [id, counts.map(&:to_i)] }
  end

  def show
    @product = Product.find_by!(slug: params[:slug])
    @status = STATUSES.include?(params[:status]) ? params[:status] : "waiting"
    @signups = @status == "waiting" ? @product.line : @product.signups.public_send(@status).in_line.to_a
    @signups = @signups.select { |signup| signup.email.include?(params[:q].strip.downcase) } if params[:q].present?
  end

  def export
    product = Product.find_by!(slug: params[:slug])
    csv = CSV.generate do |rows|
      places = product.line.each_with_index.to_h { |signup, index| [signup.id, index + 1] }
      rows << ["email", "status", "place in line", "referrals", "signed up", "confirmed", "approved", "approval", "source", "experiment", "variant", *product.question_titles]
      product.signups.in_line.each do |signup|
        rows << [signup.email, signup.status, places[signup.id], signup.effective_referrals, signup.created_at&.iso8601, signup.confirmed_at&.iso8601,
          signup.approved_at&.iso8601, signup.approval_state, signup.source, signup.experiment, signup.variant,
          *product.question_titles.map { |q| signup.answers[q] }].map { |cell| spreadsheet_safe(cell) }
      end
    end
    send_data csv, filename: "#{product.slug}-waitlist-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  private

  # A cell starting with = + - @ would run as a formula in a spreadsheet.
  def spreadsheet_safe(cell)
    cell.is_a?(String) && cell.match?(/\A[=+\-@\t\r]/) ? "'#{cell}" : cell
  end
end
