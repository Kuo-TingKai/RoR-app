class OrderForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  # 屬性定義
  attribute :store_id, :integer
  attribute :user_id, :integer
  attribute :billing_address_id, :integer
  attribute :shipping_address_id, :integer
  attribute :payment_method_id, :integer
  attribute :shipping_method_id, :integer
  attribute :discount_codes, array: true, default: []
  attribute :notes, :string
  attribute :currency, :string, default: 'TWD'
  attribute :order_items_attributes, array: true, default: []

  # 關聯
  attr_accessor :store, :user, :order

  # 驗證
  validates :store_id, presence: true
  validates :user_id, presence: true
  validates :billing_address_id, presence: true
  validates :shipping_address_id, presence: true
  validates :payment_method_id, presence: true
  validates :shipping_method_id, presence: true
  validates :currency, presence: true, length: { is: 3 }
  validates :order_items_attributes, presence: true
  validate :validate_store_exists
  validate :validate_user_exists
  validate :validate_addresses_belong_to_user
  validate :validate_payment_method_belongs_to_store
  validate :validate_shipping_method_belongs_to_store
  validate :validate_order_items
  validate :validate_discount_codes
  validate :validate_minimum_order_amount

  def initialize(attributes = {})
    super
    @order = nil
    load_associations
  end

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      create_order
      create_order_items
      apply_discounts
      calculate_totals
      process_order
      
      true
    rescue StandardError => e
      errors.add(:base, e.message)
      false
    end
  end

  def update(attributes = {})
    assign_attributes(attributes)
    return false unless valid?

    ActiveRecord::Base.transaction do
      update_order
      update_order_items
      apply_discounts
      calculate_totals
      
      true
    rescue StandardError => e
      errors.add(:base, e.message)
      false
    end
  end

  def order_items_attributes=(attributes)
    @order_items_attributes = attributes.values.map do |item_attrs|
      OrderItemForm.new(item_attrs)
    end
  end

  def total_amount
    return 0 unless order
    order.total_amount
  end

  def subtotal_amount
    return 0 unless order
    order.subtotal_amount
  end

  def tax_amount
    return 0 unless order
    order.tax_amount
  end

  def shipping_amount
    return 0 unless order
    order.shipping_amount
  end

  def discount_amount
    return 0 unless order
    order.discount_amount
  end

  def items_count
    order_items_attributes.sum(&:quantity)
  end

  def unique_items_count
    order_items_attributes.count
  end

  def estimated_delivery_date
    return nil unless shipping_method
    Time.current + shipping_method.delivery_days.days
  end

  def shipping_method
    @shipping_method ||= store&.shipping_methods&.find_by(id: shipping_method_id)
  end

  def payment_method
    @payment_method ||= store&.payment_methods&.find_by(id: payment_method_id)
  end

  def billing_address
    @billing_address ||= user&.addresses&.find_by(id: billing_address_id)
  end

  def shipping_address
    @shipping_address ||= user&.addresses&.find_by(id: shipping_address_id)
  end

  def available_payment_methods
    store&.payment_methods_available || []
  end

  def available_shipping_methods
    store&.shipping_methods_available || []
  end

  def available_addresses
    user&.addresses || []
  end

  def available_products
    store&.products&.active || []
  end

  def valid_discount_codes
    return [] unless store && discount_codes.any?
    
    discount_codes.select do |code|
      discount = store.discounts.find_by(code: code, is_active: true)
      discount&.is_valid?
    end
  end

  def invalid_discount_codes
    discount_codes - valid_discount_codes
  end

  def total_discount_amount
    valid_discount_codes.sum do |code|
      discount = store.discounts.find_by(code: code)
      calculate_discount_amount(discount)
    end
  end

  def shipping_cost
    return 0 unless shipping_method
    
    case shipping_method.calculation_method
    when 'fixed'
      shipping_method.base_cost
    when 'weight_based'
      total_weight = order_items_attributes.sum { |item| item.weight * item.quantity }
      shipping_method.base_cost + (total_weight * shipping_method.weight_rate)
    when 'price_based'
      if subtotal_amount >= shipping_method.free_shipping_threshold
        0
      else
        shipping_method.base_cost
      end
    else
      0
    end
  end

  def tax_amount_calculated
    tax_rate = store&.tax_rate || 0
    return 0 if tax_rate.zero?
    
    taxable_amount = subtotal_amount - total_discount_amount
    (taxable_amount * tax_rate / 100).round(2)
  end

  def total_amount_calculated
    subtotal_amount + tax_amount_calculated + shipping_cost - total_discount_amount
  end

  def minimum_order_amount
    store&.minimum_order_amount || 0
  end

  def meets_minimum_order?
    subtotal_amount >= minimum_order_amount
  end

  def can_checkout?
    valid? && meets_minimum_order? && items_count > 0
  end

  def checkout_errors
    errors = []
    errors << "訂單金額未達最低消費 #{minimum_order_amount}" unless meets_minimum_order?
    errors << "購物車為空" if items_count.zero?
    errors += self.errors.full_messages
    errors
  end

  private

  def load_associations
    @store = Store.find_by(id: store_id) if store_id
    @user = User.find_by(id: user_id) if user_id
  end

  def validate_store_exists
    return if store
    errors.add(:store_id, "商店不存在")
  end

  def validate_user_exists
    return if user
    errors.add(:user_id, "使用者不存在")
  end

  def validate_addresses_belong_to_user
    return unless user
    
    unless user.addresses.exists?(id: billing_address_id)
      errors.add(:billing_address_id, "帳單地址不存在")
    end
    
    unless user.addresses.exists?(id: shipping_address_id)
      errors.add(:shipping_address_id, "收貨地址不存在")
    end
  end

  def validate_payment_method_belongs_to_store
    return unless store
    
    unless store.payment_methods.exists?(id: payment_method_id)
      errors.add(:payment_method_id, "付款方式不存在")
    end
  end

  def validate_shipping_method_belongs_to_store
    return unless store
    
    unless store.shipping_methods.exists?(id: shipping_method_id)
      errors.add(:shipping_method_id, "運送方式不存在")
    end
  end

  def validate_order_items
    return if order_items_attributes.any?
    errors.add(:order_items_attributes, "訂單必須包含至少一個商品")
  end

  def validate_discount_codes
    invalid_codes = invalid_discount_codes
    return if invalid_codes.empty?
    
    invalid_codes.each do |code|
      errors.add(:discount_codes, "折扣碼 #{code} 無效或已過期")
    end
  end

  def validate_minimum_order_amount
    return if meets_minimum_order?
    errors.add(:base, "訂單金額未達最低消費 #{minimum_order_amount}")
  end

  def create_order
    @order = Order.create!(
      store: store,
      user: user,
      billing_address: billing_address,
      shipping_address: shipping_address,
      currency: currency,
      notes: notes,
      status: :pending,
      payment_status: :unpaid,
      fulfillment_status: :unfulfilled
    )
  end

  def update_order
    order.update!(
      billing_address: billing_address,
      shipping_address: shipping_address,
      currency: currency,
      notes: notes
    )
  end

  def create_order_items
    order_items_attributes.each do |item_form|
      next unless item_form.valid?
      
      order.order_items.create!(
        product: item_form.product,
        quantity: item_form.quantity,
        unit_price: item_form.unit_price,
        total_price: item_form.total_price
      )
    end
  end

  def update_order_items
    # 刪除現有項目
    order.order_items.destroy_all
    
    # 重新創建
    create_order_items
  end

  def apply_discounts
    valid_discount_codes.each do |code|
      discount = store.discounts.find_by(code: code)
      discount_amount = calculate_discount_amount(discount)
      
      order.order_discounts.create!(
        discount: discount,
        amount: discount_amount,
        discount_code: code
      )
    end
  end

  def calculate_discount_amount(discount)
    case discount.discount_type
    when 'percentage'
      (order.subtotal_amount * discount.value / 100).round(2)
    when 'fixed'
      [discount.value, order.subtotal_amount].min
    else
      0
    end
  end

  def calculate_totals
    order.calculate_totals
  end

  def process_order
    service = OrderProcessingService.new(order, user)
    service.process
  end
end

# 訂單項目表單物件
class OrderItemForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :product_id, :integer
  attribute :quantity, :integer, default: 1

  attr_accessor :product

  validates :product_id, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validate :validate_product_exists
  validate :validate_product_available
  validate :validate_quantity_available

  def initialize(attributes = {})
    super
    load_product
  end

  def unit_price
    return 0 unless product
    product.price
  end

  def total_price
    unit_price * quantity
  end

  def weight
    return 0 unless product
    product.shipping_weight
  end

  def available_quantity
    return 0 unless product
    product.available_quantity
  end

  def in_stock?
    return false unless product
    product.in_stock?
  end

  private

  def load_product
    @product = Product.find_by(id: product_id) if product_id
  end

  def validate_product_exists
    return if product
    errors.add(:product_id, "商品不存在")
  end

  def validate_product_available
    return unless product
    return if product.active?
    errors.add(:product_id, "商品已下架")
  end

  def validate_quantity_available
    return unless product && quantity
    return unless product.track_inventory?
    
    if quantity > available_quantity
      errors.add(:quantity, "庫存不足。可用: #{available_quantity}")
    end
  end
end 