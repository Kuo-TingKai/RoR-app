require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EcommercePlatform
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # 設定時區
    config.time_zone = 'Asia/Taipei'
    config.active_record.default_timezone = :local

    # 設定語言
    config.i18n.default_locale = :'zh-TW'
    config.i18n.available_locales = [:en, :'zh-TW']

    # 自動載入 lib 目錄
    config.autoload_paths += %W(#{config.root}/lib)
    config.eager_load_paths += %W(#{config.root}/lib)

    # 設定 CORS
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource '*',
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options, :head],
          credentials: false
      end
    end

    # 設定 API 模式
    config.api_only = true

    # 設定 Sidekiq
    config.active_job.queue_adapter = :sidekiq

    # 設定快取
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
      connect_timeout: 30,
      read_timeout: 0.2,
      write_timeout: 0.2,
      reconnect_attempts: 1
    }

    # 設定 Session
    config.session_store :cache_store, key: '_ecommerce_platform_session'

    # 設定 Action Cable
    config.action_cable.mount_path = '/cable'
    config.action_cable.allowed_request_origins = [
      /http:\/\/*/,
      /https:\/\/*/
    ]
  end
end 