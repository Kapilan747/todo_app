Rails.application.routes.draw do
  root "products#index"

  resources :products

  get "/up", to: proc { [200, {}, ["OK"]] }
end
