source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.0'

# Rails 核心
gem 'rails', '~> 7.0.0'
gem 'puma', '~> 5.0'
gem 'bootsnap', '>= 1.4.4', require: false

# 資料庫
gem 'sqlite3', '~> 1.4'
gem 'redis', '~> 4.8'
gem 'elasticsearch-rails', '~> 7.0'

# API 相關
gem 'rack-cors'
gem 'jbuilder', '~> 2.7'
gem 'active_model_serializers', '~> 0.10.0'

# 認證與授權
gem 'devise'
gem 'devise_token_auth'
gem 'pundit'
gem 'jwt'

# 效能優化
gem 'bullet'
gem 'rack-attack'
gem 'sidekiq'
gem 'whenever', require: false
gem 'fast_jsonapi'

# 快取
gem 'dalli'
gem 'hiredis'

# 搜尋
gem 'searchkick'

# 檔案處理
gem 'aws-sdk-s3', require: false
gem 'image_processing', '~> 1.2'

# 表單處理
gem 'simple_form'
gem 'cocoon'

# 驗證
gem 'dry-validation'
gem 'dry-types'

# 監控與日誌
gem 'sentry-ruby'
gem 'sentry-rails'
gem 'lograge'

# 測試
group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'shoulda-matchers'
  gem 'database_cleaner-active_record'
  gem 'vcr'
  gem 'webmock'
  gem 'capybara'
  gem 'selenium-webdriver'
end

group :development do
  gem 'listen', '~> 3.3'
  gem 'spring'
  gem 'annotate'
  gem 'brakeman'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'pry-rails'
  gem 'pry-byebug'
end

group :test do
  gem 'simplecov', require: false
  gem 'timecop'
end 