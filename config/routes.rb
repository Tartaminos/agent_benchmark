Rails.application.routes.draw do
  namespace :admin do
    resources :orders, only: :index
  end

  namespace :api, defaults: { format: :json } do
    get "sellers/:seller_id/orders", to: "seller_orders#index"
    post "sellers/:seller_id/reports", to: "seller_performance_reports#create"
    resources :reports, only: :show, param: :report_id do
      get :download, on: :member
    end
    resources :orders, only: %i[index show], param: :order_id
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
