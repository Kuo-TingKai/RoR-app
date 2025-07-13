Rails.application.routes.draw do
  # API 路由
  namespace :api do
    namespace :v1 do
      # 認證相關
      devise_for :users, controllers: {
        sessions: 'api/v1/sessions',
        registrations: 'api/v1/registrations',
        passwords: 'api/v1/passwords'
      }

      # 商店相關
      resources :stores, only: [:index, :show] do
        # 商品相關
        resources :products, only: [:index, :show] do
          member do
            post :add_to_cart
            post :add_to_wishlist
            delete :remove_from_wishlist
            post :track_view
            post :track_add_to_cart
          end
          
          resources :reviews, only: [:index, :create, :update, :destroy]
        end

        # 分類相關
        resources :categories, only: [:index, :show] do
          resources :products, only: [:index]
        end

        # 訂單相關
        resources :orders, only: [:index, :show, :create, :update, :destroy] do
          member do
            post :cancel
            post :confirm
            post :ship
            post :deliver
            post :complete
            post :refund
          end
          
          collection do
            get :analytics
            get :export
          end
        end

        # 購物車相關
        resource :cart, only: [:show, :update, :destroy] do
          member do
            post :add_item
            delete :remove_item
            post :update_quantity
            post :clear
            post :apply_discount
            delete :remove_discount
          end
        end

        # 願望清單相關
        resource :wishlist, only: [:show] do
          member do
            post :add_item
            delete :remove_item
            post :move_to_cart
          end
        end

        # 搜尋相關
        get :search, to: 'search#index'
      end

      # 使用者相關
      resource :profile, only: [:show, :update] do
        member do
          get :orders
          get :wishlist
          get :addresses
          get :payment_methods
        end
      end

      resources :addresses, only: [:index, :show, :create, :update, :destroy]
      resources :payment_methods, only: [:index, :show, :create, :update, :destroy]

      # 管理員相關
      namespace :admin do
        resources :stores, only: [:index, :show, :update] do
          member do
            post :approve
            post :suspend
            post :activate
          end
          
          resources :orders, only: [:index, :show, :update] do
            member do
              post :cancel
              post :confirm
              post :ship
              post :deliver
              post :complete
              post :refund
            end
          end
          
          resources :products, only: [:index, :show, :create, :update, :destroy] do
            member do
              post :activate
              post :deactivate
              post :feature
              post :unfeature
            end
          end
          
          resources :users, only: [:index, :show, :update] do
            member do
              post :suspend
              post :activate
            end
          end
          
          get :analytics, to: 'analytics#index'
          get :reports, to: 'reports#index'
        end
      end

      # 系統相關
      get :health, to: 'health#check'
      get :version, to: 'version#show'
    end
  end

  # WebSocket 路由
  mount ActionCable.server => '/cable'

  # 根路由
  root 'home#index'

  # 健康檢查
  get '/health', to: 'health#check'

  # 404 處理
  match '*path', to: 'application#not_found', via: :all
end 