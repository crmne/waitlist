Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Public: one form per product, as a page, a plain HTML form target or JSON.
  get "p/:product", to: "signups#new", as: :product_form
  post "p/:product/signups", to: "signups#create", as: :product_signups
  match "p/:product/signups", to: "signups#preflight", via: :options
  get "p/:product/thanks", to: "signups#thanks", as: :product_thanks

  # Links from the confirmation email. GET only shows a button, so a mail
  # scanner that follows links can't confirm or delete anyone.
  get "confirm/:token", to: "confirmations#show", as: :confirmation
  post "confirm/:token", to: "confirmations#create"
  get "leave/:token", to: "leaves#show", as: :leave
  post "leave/:token", to: "leaves#create"

  namespace :admin do
    root "products#index"
    resources :products, only: %i[index show], param: :slug do
      get :export, on: :member
    end
    resources :signups, only: :destroy do
      member do
        post :approve
        post :register_licence
        get :delete, action: :confirm_delete
      end
    end
  end

  root to: redirect("https://plenty.is")
end
