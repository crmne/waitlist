namespace :getwaitlist do
  desc "Import GetWaitlist signups (JSON on stdin) into PRODUCT. Dry run unless APPLY=1. Prints counts only."
  task :import, [:product] => :environment do |_, args|
    product = Product.find_by!(slug: args.fetch(:product))
    rows = JSON.parse($stdin.read)
    abort "Expected a JSON array of signups on stdin" unless rows.is_a?(Array)
    import = GetwaitlistImport.new(product:, rows:, unconfirmed: ENV["UNCONFIRMED"] == "1")
    apply = ENV["APPLY"] == "1"
    plan = apply ? import.apply! : import.plan
    puts JSON.pretty_generate({ product: product.slug, applied: apply, rows: rows.size, **plan.counts })
    puts "Dry run: nothing written. Rerun with APPLY=1 to import." unless apply
  end

  desc "Queue one reminder to each imported unconfirmed signup of PRODUCT that has none. Dry run unless APPLY=1."
  task :remind, [:product] => :environment do |_, args|
    product = Product.find_by!(slug: args.fetch(:product))
    due = product.signups.unconfirmed.where(source: GetwaitlistImport::SOURCE, reminder_sent_at: nil).where.not(confirm_by: nil)
    if ENV["APPLY"] == "1"
      puts JSON.generate(product: product.slug, queued: GetwaitlistImport.remind(product))
    else
      puts JSON.generate(product: product.slug, would_queue: due.count)
      puts "Dry run: nothing sent. Rerun with APPLY=1 to queue the emails."
    end
  end
end
