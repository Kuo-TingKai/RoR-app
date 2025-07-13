class Product < ApplicationRecord
  # 關聯
  belongs_to :store
  belongs_to :category, optional: true
  has_many :product_variants, dependent: :destroy
  has_many :product_images, dependent: :destroy
  has_many :order_items, dependent: :destroy
  has_many :orders, through: :order_items
  has_many :product_reviews, dependent: :destroy
  has_many :product_tags, dependent: :destroy
  has_many :tags, through: :product_tags
  has_many :inventory_items, dependent: :destroy
  has_many :product_discounts, dependent: :destroy
  has_many :discounts, through: :product_discounts
  has_many :product_analytics, dependent: :destroy
  has_many :wishlist_items, dependent: :destroy
  has_many :cart_items, dependent: :destroy

  # 驗證
  validates :name, presence: true, length: { maximum: 200 }
  validates :sku, presence: true, uniqueness: { scope: :store_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :compare_at_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :weight, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :height, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :width, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :depth, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :slug, presence: true, uniqueness: { scope: :store_id }

  # 回調
  before_validation :generate_sku, on: :create
  before_validation :generate_slug, on: :create
  before_save :update_search_terms
  after_create :create_inventory_item
  after_update :update_inventory_if_needed

  # 搜尋
  searchkick word_start: [:name, :description, :tags, :search_terms],
             callbacks: :async

  # 列舉
  enum status: { draft: 0, active: 1, inactive: 2, archived: 3 }
  enum product_type: { simple: 0, variable: 1, bundle: 2, digital: 3 }
  enum inventory_tracking: { none: 0, simple: 1, advanced: 2 }

  # 範圍
  scope :active, -> { where(status: :active) }
  scope :featured, -> { where(is_featured: true) }
  scope :on_sale, -> { where('compare_at_price > price') }
  scope :in_stock, -> { joins(:inventory_items).where('inventory_items.quantity > 0') }
  scope :out_of_stock, -> { joins(:inventory_items).where(inventory_items: { quantity: 0 }) }
  scope :low_stock, -> { joins(:inventory_items).where('inventory_items.quantity <= inventory_items.reorder_point') }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { joins(:order_items).group('products.id').order('COUNT(order_items.id) DESC') }
  scope :by_price_range, ->(min, max) { where(price: min..max) }
  scope :by_category, ->(category_id) { where(category_id: category_id) }

  # 方法
  def display_name
    name
  end

  def display_price
    if on_sale?
      compare_at_price
    else
      price
    end
  end

  def sale_price
    price
  end

  def discount_percentage
    return 0 unless compare_at_price && compare_at_price > price
    ((compare_at_price - price) / compare_at_price * 100).round(2)
  end

  def on_sale?
    compare_at_price.present? && compare_at_price > price
  end

  def profit_margin
    return 0 unless cost_price && price > 0
    ((price - cost_price) / price * 100).round(2)
  end

  def total_quantity
    inventory_items.sum(:quantity)
  end

  def available_quantity
    inventory_items.sum(:available_quantity)
  end

  def in_stock?
    available_quantity > 0
  end

  def out_of_stock?
    available_quantity.zero?
  end

  def low_stock?
    inventory_items.any? { |item| item.low_stock? }
  end

  def primary_image
    product_images.order(:position).first
  end

  def primary_image_url
    primary_image&.image_url
  end

  def all_images
    product_images.order(:position)
  end

  def image_urls
    all_images.map(&:image_url)
  end

  def variants_count
    product_variants.count
  end

  def has_variants?
    product_variants.any?
  end

  def variant_options
    product_variants.map(&:option_values).flatten.uniq
  end

  def min_price
    if has_variants?
      product_variants.minimum(:price) || price
    else
      price
    end
  end

  def max_price
    if has_variants?
      product_variants.maximum(:price) || price
    else
      price
    end
  end

  def average_rating
    return 0 if product_reviews.empty?
    product_reviews.average(:rating).round(2)
  end

  def reviews_count
    product_reviews.count
  end

  def total_sold
    order_items.sum(:quantity)
  end

  def total_revenue
    order_items.joins(:order).where(orders: { status: :completed }).sum('order_items.quantity * order_items.unit_price')
  end

  def views_count
    product_analytics.sum(:views)
  end

  def add_to_cart_count
    product_analytics.sum(:add_to_cart)
  end

  def conversion_rate
    return 0 if views_count.zero?
    (total_sold.to_f / views_count * 100).round(2)
  end

  def wishlist_count
    wishlist_items.count
  end

  def cart_count
    cart_items.count
  end

  def seo_title
    seo_meta_title.presence || name
  end

  def seo_description
    seo_meta_description.presence || description&.truncate(160)
  end

  def seo_keywords
    seo_meta_keywords.presence || tags.join(', ')
  end

  def url
    "/stores/#{store.slug}/products/#{slug}"
  end

  def full_url
    "#{store.website_url}#{url}"
  end

  def dimensions
    [length, width, height].compact.join(' x ')
  end

  def weight_with_unit
    return nil unless weight
    "#{weight} #{weight_unit}"
  end

  def volume
    return nil unless length && width && height
    (length * width * height).round(2)
  end

  def shipping_weight
    weight || 0
  end

  def requires_shipping?
    !digital?
  end

  def downloadable?
    digital?
  end

  def track_inventory?
    inventory_tracking != 'none'
  end

  def can_track_inventory?
    track_inventory? && store.has_inventory_management?
  end

  def update_inventory(quantity, operation: :add, location: nil)
    return unless can_track_inventory?
    
    inventory_item = location ? inventory_items.find_by(location: location) : inventory_items.first
    return unless inventory_item
    
    case operation
    when :add
      inventory_item.increment!(:quantity, quantity)
    when :subtract
      inventory_item.decrement!(:quantity, quantity)
    when :set
      inventory_item.update!(quantity: quantity)
    end
  end

  def reserve_inventory(quantity)
    return unless can_track_inventory?
    
    inventory_items.each do |item|
      available = item.available_quantity
      if available >= quantity
        item.increment!(:reserved_quantity, quantity)
        break
      else
        item.increment!(:reserved_quantity, available)
        quantity -= available
      end
    end
  end

  def release_inventory(quantity)
    return unless can_track_inventory?
    
    inventory_items.each do |item|
      reserved = item.reserved_quantity
      if reserved >= quantity
        item.decrement!(:reserved_quantity, quantity)
        break
      else
        item.update!(reserved_quantity: 0)
        quantity -= reserved
      end
    end
  end

  def add_review(user, rating, comment = nil)
    product_reviews.create!(
      user: user,
      rating: rating,
      comment: comment
    )
  end

  def add_to_wishlist(user)
    wishlist_items.find_or_create_by(user: user)
  end

  def remove_from_wishlist(user)
    wishlist_items.find_by(user: user)&.destroy
  end

  def in_wishlist?(user)
    wishlist_items.exists?(user: user)
  end

  def track_view(user = nil)
    product_analytics.create!(
      user: user,
      views: 1,
      viewed_at: Time.current
    )
  end

  def track_add_to_cart(user = nil)
    product_analytics.create!(
      user: user,
      add_to_cart: 1,
      added_to_cart_at: Time.current
    )
  end

  def update_search_terms
    self.search_terms = [
      name,
      description,
      sku,
      tags.join(' '),
      category&.name
    ].compact.join(' ')
  end

  def duplicate
    new_product = dup
    new_product.name = "#{name} (複製)"
    new_product.sku = nil
    new_product.slug = nil
    new_product.status = :draft
    new_product.is_featured = false
    new_product.save!
    
    # 複製圖片
    product_images.each do |image|
      new_product.product_images.create!(
        image: image.image,
        position: image.position,
        alt_text: image.alt_text
      )
    end
    
    # 複製標籤
    tags.each do |tag|
      new_product.tags << tag
    end
    
    new_product
  end

  private

  def generate_sku
    return if sku.present?
    
    base_sku = name.parameterize.upcase[0..7]
    counter = 0
    new_sku = base_sku
    
    while Product.exists?(sku: new_sku, store: store)
      counter += 1
      new_sku = "#{base_sku}#{counter.to_s.rjust(3, '0')}"
    end
    
    self.sku = new_sku
  end

  def generate_slug
    return if slug.present?
    
    base_slug = name.parameterize
    counter = 0
    new_slug = base_slug
    
    while Product.exists?(slug: new_slug, store: store)
      counter += 1
      new_slug = "#{base_slug}-#{counter}"
    end
    
    self.slug = new_slug
  end

  def create_inventory_item
    return unless track_inventory?
    
    inventory_items.create!(
      quantity: 0,
      available_quantity: 0,
      reserved_quantity: 0,
      reorder_point: 10,
      location: '主要倉庫'
    )
  end

  def update_inventory_if_needed
    return unless saved_change_to_inventory_tracking?
    
    if track_inventory? && inventory_items.empty?
      create_inventory_item
    elsif !track_inventory?
      inventory_items.destroy_all
    end
  end

  def search_data
    {
      name: name,
      description: description,
      sku: sku,
      tags: tags.map(&:name),
      search_terms: search_terms,
      category_name: category&.name,
      store_name: store.name,
      status: status,
      product_type: product_type,
      price: price,
      compare_at_price: compare_at_price,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end 