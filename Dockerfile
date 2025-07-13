# 使用官方 Ruby 映像
FROM ruby:3.2.0-alpine

# 設定環境變數
ENV RAILS_ENV=production
ENV RAILS_SERVE_STATIC_FILES=true
ENV RAILS_LOG_TO_STDOUT=true

# 安裝系統依賴
RUN apk add --no-cache \
    build-base \
    tzdata \
    nodejs \
    yarn \
    mysql-dev \
    postgresql-dev \
    sqlite-dev \
    imagemagick \
    git \
    curl \
    bash

# 設定工作目錄
WORKDIR /app

# 複製 Gemfile 和 Gemfile.lock
COPY Gemfile Gemfile.lock ./

# 安裝 Ruby gems
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# 複製應用程式程式碼
COPY . .

# 預編譯資產
RUN bundle exec rake assets:precompile

# 建立非 root 使用者
RUN addgroup -g 1000 -S app && \
    adduser -u 1000 -S app -G app

# 變更檔案擁有者
RUN chown -R app:app /app

# 切換到非 root 使用者
USER app

# 暴露端口
EXPOSE 3000

# 健康檢查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# 啟動命令
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"] 