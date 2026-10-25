# A product's brand files for its emails (logo, fonts), from the folder its
# products file names (brand.dir). Only png, jpeg, gif, css, woff2 and txt.
class BrandsController < PublicController
  def show
    product = Product.find_by!(slug: params[:product])
    path = product.brand_file("#{params[:file]}.#{params[:format]}") or raise ActiveRecord::RecordNotFound
    response.headers["Cache-Control"] = "public, max-age=86400"
    response.headers["Access-Control-Allow-Origin"] = "*" if path.extname == ".woff2"
    send_file path, disposition: "inline", type: Rack::Mime.mime_type(path.extname)
  end
end
