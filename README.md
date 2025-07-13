# 電商開店平台 (Ecommerce Platform)

這是一個基於 Ruby on Rails 7 開發的現代化電商開店平台，提供完整的電商解決方案，包括商店管理、商品管理、訂單處理、庫存管理、客戶管理等核心功能。

## 🚀 功能特色

### 核心功能
- **多商店管理**: 支援多個商店獨立運營
- **商品管理**: 完整的商品 CRUD、分類、變體、庫存管理
- **訂單處理**: 完整的訂單生命週期管理
- **客戶管理**: 客戶資料、地址、付款方式管理
- **購物車系統**: 購物車、願望清單功能
- **搜尋功能**: 基於 Elasticsearch 的全文搜尋
- **評價系統**: 商品評價與評分

### 進階功能
- **庫存管理**: 即時庫存追蹤、低庫存警告
- **折扣系統**: 多種折扣類型支援
- **運送管理**: 多種運送方式、追蹤號碼
- **付款整合**: 多種付款方式支援
- **分析報表**: 銷售分析、客戶分析
- **通知系統**: 電子郵件、簡訊通知
- **API 支援**: RESTful API 完整支援

### 技術特色
- **效能優化**: Redis 快取、資料庫索引優化
- **背景工作**: Sidekiq 處理非同步任務
- **監控系統**: Prometheus + Grafana 監控
- **容器化**: Docker + Docker Compose 部署
- **自動化測試**: RSpec 完整測試覆蓋
- **CI/CD**: GitHub Actions 自動化部署

## 🛠 技術架構

### 後端技術
- **Ruby on Rails 7.0**: 主要框架
- **Ruby 3.2.0**: 程式語言
- **MySQL 8.0**: 主要資料庫
- **Redis 7**: 快取與 Session 儲存
- **Elasticsearch 7.17**: 搜尋引擎
- **Sidekiq**: 背景工作處理

### 前端技術
- **API 優先**: RESTful API 設計
- **JSON API**: 標準化 API 回應格式
- **WebSocket**: Action Cable 即時通訊

### 部署與監控
- **Docker**: 容器化部署
- **Nginx**: 反向代理伺服器
- **Prometheus**: 監控系統
- **Grafana**: 儀表板
- **Sentry**: 錯誤追蹤

## 📋 系統需求

- Ruby 3.2.0+
- MySQL 8.0+
- Redis 7+
- Elasticsearch 7.17+
- Node.js 16+
- Docker & Docker Compose

## 🚀 快速開始

### 使用 Docker Compose (推薦)

1. **克隆專案**
```bash
git clone <repository-url>
cd ecommerce-platform
```

2. **設定環境變數**
```bash
cp .env.example .env
# 編輯 .env 檔案，設定必要的環境變數
```

3. **啟動服務**
```bash
docker-compose up -d
```

4. **執行資料庫遷移**
```bash
docker-compose exec web bundle exec rails db:create db:migrate db:seed
```

5. **建立搜尋索引**
```bash
docker-compose exec web bundle exec rails searchkick:reindex:all
```

6. **訪問應用程式**
- 應用程式: http://localhost:3000
- Grafana 儀表板: http://localhost:3001 (admin/admin)

### 本地開發環境

1. **安裝依賴**
```bash
bundle install
npm install
```

2. **設定資料庫**
```bash
rails db:create db:migrate db:seed
```

3. **啟動服務**
```bash
# 終端機 1: Rails 伺服器
rails server

# 終端機 2: Sidekiq
bundle exec sidekiq

# 終端機 3: Elasticsearch
elasticsearch

# 終端機 4: Redis
redis-server
```

## 📁 專案結構

```
ecommerce-platform/
├── app/
│   ├── controllers/          # 控制器
│   │   └── api/v1/          # API 控制器
│   ├── models/              # 資料模型
│   ├── services/            # 服務物件
│   ├── forms/               # 表單物件
│   ├── serializers/         # API 序列化器
│   ├── workers/             # 背景工作
│   └── mailers/             # 郵件發送器
├── config/                  # 配置檔案
├── db/                      # 資料庫遷移與種子資料
├── lib/                     # 自定義函式庫
├── spec/                    # 測試檔案
├── docker-compose.yml       # Docker Compose 配置
├── Dockerfile              # Docker 映像配置
└── README.md               # 專案說明
```

## 🔧 配置說明

### 環境變數

主要環境變數設定：

```bash
# 資料庫
DATABASE_URL=mysql2://user:password@localhost:3306/database_name
DATABASE_USERNAME=root
DATABASE_PASSWORD=password

# Redis
REDIS_URL=redis://localhost:6379/1

# Elasticsearch
ELASTICSEARCH_URL=http://localhost:9200

# 應用程式
RAILS_ENV=production
SECRET_KEY_BASE=your_secret_key_base

# 第三方服務
SENTRY_DSN=your_sentry_dsn
AWS_ACCESS_KEY_ID=your_aws_key
AWS_SECRET_ACCESS_KEY=your_aws_secret
```

### 資料庫配置

主要資料表結構：

- `users`: 使用者資料
- `stores`: 商店資料
- `products`: 商品資料
- `orders`: 訂單資料
- `order_items`: 訂單項目
- `inventory_items`: 庫存項目
- `payments`: 付款記錄
- `shipments`: 運送記錄

## 🧪 測試

### 執行測試
```bash
# 執行所有測試
bundle exec rspec

# 執行特定測試
bundle exec rspec spec/models/order_spec.rb

# 執行測試並生成覆蓋率報告
COVERAGE=true bundle exec rspec
```

### 測試覆蓋率
專案使用 SimpleCov 進行測試覆蓋率統計，目標覆蓋率 > 90%。

## 📊 監控與日誌

### 監控指標
- 應用程式效能 (響應時間、吞吐量)
- 資料庫效能 (查詢時間、連接數)
- 系統資源 (CPU、記憶體、磁碟)
- 業務指標 (訂單量、營收、轉換率)

### 日誌管理
- 應用程式日誌: `log/`
- 錯誤追蹤: Sentry
- 監控儀表板: Grafana

## 🔒 安全性

### 安全措施
- JWT 認證
- CSRF 保護
- SQL 注入防護
- XSS 防護
- 速率限制
- 輸入驗證

### 權限管理
- 基於角色的權限控制 (RBAC)
- Pundit 授權框架
- API 權限驗證

## 🚀 部署

### 生產環境部署

1. **準備伺服器**
```bash
# 安裝 Docker 和 Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

2. **部署應用程式**
```bash
# 克隆專案
git clone <repository-url>
cd ecommerce-platform

# 設定環境變數
cp .env.example .env
# 編輯 .env 檔案

# 啟動服務
docker-compose -f docker-compose.prod.yml up -d

# 執行資料庫遷移
docker-compose exec web bundle exec rails db:migrate
```

3. **設定 SSL 憑證**
```bash
# 使用 Let's Encrypt
certbot --nginx -d your-domain.com
```

### CI/CD 流程

使用 GitHub Actions 自動化部署：

1. 推送到 `main` 分支
2. 自動執行測試
3. 建置 Docker 映像
4. 部署到生產環境

## 📈 效能優化

### 資料庫優化
- 索引優化
- 查詢優化
- 連接池配置
- 讀寫分離

### 快取策略
- Redis 快取
- 頁面快取
- 片段快取
- HTTP 快取

### 背景工作
- Sidekiq 處理非同步任務
- 批次處理大量資料
- 定時任務排程

## 🤝 貢獻指南

1. Fork 專案
2. 建立功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交變更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 開啟 Pull Request

## 📄 授權

本專案採用 MIT 授權條款 - 詳見 [LICENSE](LICENSE) 檔案

## 📞 支援

如有問題或建議，請：

1. 查看 [Issues](../../issues)
2. 建立新的 Issue
3. 聯繫開發團隊

## 🔄 更新日誌

### v1.0.0 (2024-01-01)
- 初始版本發布
- 基本電商功能
- API 支援
- Docker 部署

---

**注意**: 這是一個示範專案，展示了現代 Rails 應用程式的最佳實踐。在生產環境使用前，請確保進行適當的安全審查和測試。 