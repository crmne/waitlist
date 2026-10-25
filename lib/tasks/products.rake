namespace :products do
  desc "Create or update the products in config/products.yml (never deletes)"
  task sync: :environment do
    Product.sync!
    puts Product.order(:slug).pluck(:slug).join(" ")
  end
end
