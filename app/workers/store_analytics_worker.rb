class StoreAnalyticsWorker
  include Sidekiq::Worker
  sidekiq_options queue: :analytics, retry: 3, backtrace: true

  def perform(store_id)
    store = Store.find(store_id)
    
    # 生成每日分析數據
    generate_daily_analytics(store)
    
    # 更新快取
    update_analytics_cache(store)
    
    # 檢查是否需要發送報告
    send_analytics_report(store) if should_send_report?(store)
    
    Rails.logger.info "Store analytics generated for store #{store_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Store not found: #{store_id}"
  rescue StandardError => e
    Rails.logger.error "Error generating analytics for store #{store_id}: #{e.message}"
    raise e
  end

  private

  def generate_daily_analytics(store)
    today = Time.current.to_date
    
    # 檢查是否已經生成過今天的數據
    return if store.store_analytics.exists?(date: today)
    
    analytics_data = {
      date: today,
      total_orders: store.orders.where(created_at: today.beginning_of_day..today.end_of_day).count,
      total_revenue: store.orders.completed.where(created_at: today.beginning_of_day..today.end_of_day).sum(:total_amount),
      total_customers: store.orders.where(created_at: today.beginning_of_day..today.end_of_day).distinct.count(:user_id),
      average_order_value: calculate_average_order_value(store, today),
      conversion_rate: calculate_conversion_rate(store, today),
      top_products: get_top_products(store, today),
      customer_segments: get_customer_segments(store, today),
      revenue_by_hour: get_revenue_by_hour(store, today),
      orders_by_status: get_orders_by_status(store, today),
      inventory_alerts: get_inventory_alerts(store),
      performance_metrics: calculate_performance_metrics(store, today)
    }
    
    store.store_analytics.create!(analytics_data)
  end

  def update_analytics_cache(store)
    cache_key = "store_analytics:#{store.id}"
    
    # 更新快取數據
    Rails.cache.write(cache_key, {
      total_orders: store.total_orders,
      total_revenue: store.total_revenue,
      average_order_value: store.average_order_value,
      total_customers: store.total_customers,
      revenue_growth_rate: store.revenue_growth_rate,
      customer_retention_rate: store.customer_retention_rate,
      average_customer_lifetime_value: store.average_customer_lifetime_value,
      last_updated: Time.current
    }, expires_in: 1.hour)
  end

  def send_analytics_report(store)
    return unless store.has_analytics?
    
    # 檢查是否需要發送每日報告
    if should_send_daily_report?(store)
      StoreAnalyticsMailer.daily_report(store).deliver_later
    end
    
    # 檢查是否需要發送每週報告
    if should_send_weekly_report?(store)
      StoreAnalyticsMailer.weekly_report(store).deliver_later
    end
    
    # 檢查是否需要發送每月報告
    if should_send_monthly_report?(store)
      StoreAnalyticsMailer.monthly_report(store).deliver_later
    end
  end

  def calculate_average_order_value(store, date)
    orders = store.orders.completed.where(created_at: date.beginning_of_day..date.end_of_day)
    return 0 if orders.empty?
    
    orders.sum(:total_amount) / orders.count
  end

  def calculate_conversion_rate(store, date)
    # 這裡需要結合網站分析數據，暫時使用簡化版本
    orders_count = store.orders.where(created_at: date.beginning_of_day..date.end_of_day).count
    # 假設有 1000 個訪客
    visitors_count = 1000
    
    return 0 if visitors_count.zero?
    (orders_count.to_f / visitors_count * 100).round(2)
  end

  def get_top_products(store, date)
    store.products.joins(:order_items)
         .joins('JOIN orders ON orders.id = order_items.order_id')
         .where(orders: { created_at: date.beginning_of_day..date.end_of_day })
         .group('products.id')
         .order('SUM(order_items.quantity) DESC')
         .limit(10)
         .pluck('products.name', 'SUM(order_items.quantity)')
  end

  def get_customer_segments(store, date)
    customers = store.orders.where(created_at: date.beginning_of_day..date.end_of_day)
                    .group(:user_id)
                    .sum(:total_amount)
    
    segments = {
      bronze: 0,
      silver: 0,
      gold: 0,
      platinum: 0
    }
    
    customers.each do |user_id, total_spent|
      segment = case total_spent
                when 0..1000
                  :bronze
                when 1001..5000
                  :silver
                when 5001..10000
                  :gold
                else
                  :platinum
                end
      segments[segment] += 1
    end
    
    segments
  end

  def get_revenue_by_hour(store, date)
    revenue_by_hour = Array.new(24, 0)
    
    store.orders.completed
         .where(created_at: date.beginning_of_day..date.end_of_day)
         .each do |order|
      hour = order.created_at.hour
      revenue_by_hour[hour] += order.total_amount
    end
    
    revenue_by_hour
  end

  def get_orders_by_status(store, date)
    store.orders.where(created_at: date.beginning_of_day..date.end_of_day)
         .group(:status)
         .count
  end

  def get_inventory_alerts(store)
    alerts = []
    
    # 檢查庫存不足的商品
    store.products.low_stock.each do |product|
      alerts << {
        type: 'low_stock',
        product_id: product.id,
        product_name: product.name,
        current_quantity: product.total_quantity,
        reorder_point: product.inventory_items.first&.reorder_point || 10
      }
    end
    
    # 檢查缺貨的商品
    store.products.out_of_stock.each do |product|
      alerts << {
        type: 'out_of_stock',
        product_id: product.id,
        product_name: product.name
      }
    end
    
    alerts
  end

  def calculate_performance_metrics(store, date)
    orders = store.orders.where(created_at: date.beginning_of_day..date.end_of_day)
    
    {
      order_processing_time: calculate_avg_processing_time(orders),
      customer_satisfaction: calculate_customer_satisfaction(store, date),
      return_rate: calculate_return_rate(store, date),
      shipping_performance: calculate_shipping_performance(store, date)
    }
  end

  def calculate_avg_processing_time(orders)
    processing_times = []
    
    orders.each do |order|
      if order.confirmed_at && order.created_at
        processing_time = (order.confirmed_at - order.created_at) / 1.hour
        processing_times << processing_time
      end
    end
    
    return 0 if processing_times.empty?
    processing_times.sum / processing_times.count
  end

  def calculate_customer_satisfaction(store, date)
    # 基於商品評價計算滿意度
    reviews = store.products.joins(:product_reviews)
                         .where(product_reviews: { created_at: date.beginning_of_day..date.end_of_day })
    
    return 0 if reviews.empty?
    
    total_rating = reviews.sum(:rating)
    total_reviews = reviews.count
    
    (total_rating.to_f / total_reviews).round(2)
  end

  def calculate_return_rate(store, date)
    # 簡化版本，實際需要更複雜的退貨邏輯
    total_orders = store.orders.where(created_at: date.beginning_of_day..date.end_of_day).count
    returned_orders = store.orders.where(created_at: date.beginning_of_day..date.end_of_day, status: :refunded).count
    
    return 0 if total_orders.zero?
    (returned_orders.to_f / total_orders * 100).round(2)
  end

  def calculate_shipping_performance(store, date)
    shipped_orders = store.orders.where(created_at: date.beginning_of_day..date.end_of_day, status: [:shipped, :delivered, :completed])
    
    return 0 if shipped_orders.empty?
    
    on_time_deliveries = 0
    
    shipped_orders.each do |order|
      if order.estimated_delivery_date && order.delivered_at
        if order.delivered_at <= order.estimated_delivery_date
          on_time_deliveries += 1
        end
      end
    end
    
    (on_time_deliveries.to_f / shipped_orders.count * 100).round(2)
  end

  def should_send_report?(store)
    # 檢查商店設定是否需要發送報告
    store.store_settings.find_by(key: 'analytics_reports')&.value == 'true'
  end

  def should_send_daily_report?(store)
    # 檢查是否為每日報告時間（例如晚上 8 點）
    Time.current.hour == 20
  end

  def should_send_weekly_report?(store)
    # 檢查是否為每週報告時間（例如週日晚上 8 點）
    Time.current.wday == 0 && Time.current.hour == 20
  end

  def should_send_monthly_report?(store)
    # 檢查是否為每月報告時間（例如每月最後一天晚上 8 點）
    Time.current.day == Time.current.end_of_month.day && Time.current.hour == 20
  end
end 