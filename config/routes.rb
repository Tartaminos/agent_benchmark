Rails.application.routes.draw do
  namespace :admin do
    resources :orders, only: %i[index show], param: :order_id
  end

  namespace :api do
    resources :orders, only: %i[index show], param: :order_id
    resources :order_exports, only: %i[create show], param: :export_id do
      get :download, on: :member
    end
    get "sellers/:seller_id/orders", to: "seller_orders#index", as: :seller_orders
    post "sellers/:seller_id/reports", to: "seller_reports#create", as: :seller_reports
    post "sellers/:seller_id/reconciliations",
         to: "seller_reconciliations#create",
         as: :seller_reconciliations
    get "reports/:report_id", to: "reports#show", as: :report
    get "reports/:report_id/download", to: "reports#download", as: :report_download
    get "reconciliations/:reconciliation_id", to: "reconciliations#show", as: :reconciliation
    get "reconciliations/:reconciliation_id/discrepancies",
        to: "reconciliation_discrepancies#index",
        as: :reconciliation_discrepancies
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
