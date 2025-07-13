class Store < ApplicationRecord
  # 關聯
  belongs_to :user
  has_many :products, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :order_items, through: :orders
  has_many :inventory_items, dependent: :destroy
  has_many :store_settings, dependent: :destroy
  has_many :store_analytics, dependent: :destroy
  has_many :store_employees, dependent: :destroy
  has_many :employees, through: :store_employees, source: :user
  has_many :store_payment_methods, dependent: :destroy
  has_many :payment_methods, through: :store_payment_methods
  has_many :store_shipping_methods, dependent: :destroy
  has_many :shipping_methods, through: :store_shipping_methods
  has_many :store_tax_rates, dependent: :destroy
  has_many :tax_rates, through: :store_tax_rates
  has_many :store_discounts, dependent: :destroy
  has_many :discounts, through: :store_discounts
  has_many :store_notifications, dependent: :destroy
  has_many :store_reviews, dependent: :destroy
  has_many :store_media, dependent: :destroy

  # 驗證
  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :description, length: { maximum: 1000 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone, format: { with: /\A\+?[\d\s\-\(\)]+\z/ }, allow_blank: true
  validates :website_url, format: { with: URI::regexp }, allow_blank: true

  # 回調
  before_validation :generate_slug, on: :create
  before_save :normalize_website_url
  after_create :create_default_settings
  after_create :create_default_categories

  # 搜尋
  searchkick word_start: [:name, :description, :tags]

  # 列舉
  enum status: { draft: 0, active: 1, inactive: 2, suspended: 3 }
  enum store_type: { retail: 0, wholesale: 1, dropshipping: 2, marketplace: 3 }

  # 範圍
  scope :active, -> { where(status: :active) }
  scope :featured, -> { where(is_featured: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_category, ->(category) { joins(:categories).where(categories: { name: category }) }

  # 方法
  def display_name
    name
  end

  def full_address
    [address_line1, address_line2, city, state, postal_code, country].compact.join(', ')
  end

  def contact_info
    {
      email: email,
      phone: phone,
      website: website_url
    }
  end

  def social_media_links
    {
      facebook: facebook_url,
      instagram: instagram_url,
      twitter: twitter_url,
      youtube: youtube_url
    }.compact
  end

  def business_hours
    store_settings.find_by(key: 'business_hours')&.value || {}
  end

  def currency
    store_settings.find_by(key: 'currency')&.value || 'TWD'
  end

  def timezone
    store_settings.find_by(key: 'timezone')&.value || 'Asia/Taipei'
  end

  def tax_rate
    store_tax_rates.active.first&.rate || 0
  end

  def shipping_methods_available
    store_shipping_methods.active.includes(:shipping_method)
  end

  def payment_methods_available
    store_payment_methods.active.includes(:payment_method)
  end

  def total_products
    products.count
  end

  def total_orders
    orders.count
  end

  def total_revenue
    orders.completed.sum(:total_amount)
  end

  def average_order_value
    return 0 if total_orders.zero?
    total_revenue / total_orders
  end

  def total_customers
    orders.distinct.count(:user_id)
  end

  def inventory_value
    inventory_items.sum(:value)
  end

  def low_stock_products
    inventory_items.where('quantity <= reorder_point')
  end

  def out_of_stock_products
    inventory_items.where(quantity: 0)
  end

  def featured_products
    products.featured.limit(10)
  end

  def best_selling_products
    products.joins(:order_items)
           .group('products.id')
           .order('SUM(order_items.quantity) DESC')
           .limit(10)
  end

  def recent_orders
    orders.recent.limit(10)
  end

  def pending_orders
    orders.pending
  end

  def today_orders
    orders.where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
  end

  def today_revenue
    today_orders.completed.sum(:total_amount)
  end

  def monthly_revenue
    orders.completed
          .where(created_at: Time.current.beginning_of_month..Time.current.end_of_month)
          .sum(:total_amount)
  end

  def yearly_revenue
    orders.completed
          .where(created_at: Time.current.beginning_of_year..Time.current.end_of_year)
          .sum(:total_amount)
  end

  def revenue_growth_rate
    last_month = orders.completed
                      .where(created_at: 1.month.ago.beginning_of_month..1.month.ago.end_of_month)
                      .sum(:total_amount)
    
    return 0 if last_month.zero?
    ((monthly_revenue - last_month) / last_month * 100).round(2)
  end

  def customer_retention_rate
    repeat_customers = orders.group(:user_id).having('COUNT(*) > 1').count.keys.count
    total_customers = orders.distinct.count(:user_id)
    
    return 0 if total_customers.zero?
    (repeat_customers.to_f / total_customers * 100).round(2)
  end

  def average_customer_lifetime_value
    return 0 if total_customers.zero?
    (total_revenue.to_f / total_customers).round(2)
  end

  def can_accept_orders?
    active? && !suspended?
  end

  def has_inventory_management?
    store_settings.find_by(key: 'inventory_management')&.value == 'true'
  end

  def has_analytics?
    store_settings.find_by(key: 'analytics_enabled')&.value == 'true'
  end

  def has_multi_currency?
    store_settings.find_by(key: 'multi_currency')&.value == 'true'
  end

  def has_multi_language?
    store_settings.find_by(key: 'multi_language')&.value == 'true'
  end

  def update_analytics
    StoreAnalyticsWorker.perform_async(id)
  end

  def send_notification(message, type: 'info')
    store_notifications.create!(
      message: message,
      notification_type: type,
      user: user
    )
  end

  private

  def generate_slug
    return if slug.present?
    
    base_slug = name.parameterize
    counter = 0
    new_slug = base_slug
    
    while Store.exists?(slug: new_slug)
      counter += 1
      new_slug = "#{base_slug}-#{counter}"
    end
    
    self.slug = new_slug
  end

  def normalize_website_url
    return if website_url.blank?
    
    unless website_url.start_with?('http://', 'https://')
      self.website_url = "https://#{website_url}"
    end
  end

  def create_default_settings
    default_settings = {
      'currency' => 'TWD',
      'timezone' => 'Asia/Taipei',
      'inventory_management' => 'true',
      'analytics_enabled' => 'true',
      'multi_currency' => 'false',
      'multi_language' => 'false',
      'auto_fulfillment' => 'false',
      'email_notifications' => 'true',
      'sms_notifications' => 'false',
      'business_hours' => {
        'monday' => { 'open' => '09:00', 'close' => '18:00', 'closed' => false },
        'tuesday' => { 'open' => '09:00', 'close' => '18:00', 'closed' => false },
        'wednesday' => { 'open' => '09:00', 'close' => '18:00', 'closed' => false },
        'thursday' => { 'open' => '09:00', 'close' => '18:00', 'closed' => false },
        'friday' => { 'open' => '09:00', 'close' => '18:00', 'closed' => false },
        'saturday' => { 'open' => '10:00', 'close' => '16:00', 'closed' => false },
        'sunday' => { 'open' => '10:00', 'close' => '16:00', 'closed' => true }
      }
    }
    
    default_settings.each do |key, value|
      store_settings.create!(key: key, value: value)
    end
  end

  def create_default_categories
    default_categories = ['未分類', '熱門商品', '新品上市', '特價商品']
    
    default_categories.each do |category_name|
      categories.create!(
        name: category_name,
        description: "#{category_name}分類",
        is_active: true
      )
    end
  end

  def search_data
    {
      name: name,
      description: description,
      tags: tags,
      status: status,
      store_type: store_type,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end 