namespace :getwaitlist do
  desc "Import GetWaitlist signups (JSON on stdin) into PRODUCT. Dry run unless APPLY=1. Prints counts only."
  task :import, [:product] => :environment do |_, args|
    product = Product.find_by!(slug: args.fetch(:product))
    rows = JSON.parse($stdin.read)
    abort "Expected a JSON array of signups on stdin" unless rows.is_a?(Array)
    import = GetwaitlistImport.new(product:, rows:)
    apply = ENV["APPLY"] == "1"
    plan = apply ? import.apply! : import.plan
    puts JSON.pretty_generate({ product: product.slug, applied: apply, rows: rows.size, **plan.counts })
    puts "Dry run: nothing written. Rerun with APPLY=1 to import." unless apply
  end
end
