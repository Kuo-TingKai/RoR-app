class Order < ApplicationRecord
  # 關聯
  belongs_to :store
  belongs_to :user
  belongs_to :billing_address, class_name: 'Address', optional: true
  belongs_to :shipping_address, class_name: 'Address', optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  has_many :order_payments, dependent: :destroy
  has_many :payments, through: :order_payments
  has_many :order_shipments, dependent: :destroy
  has_many :shipments, through: :order_shipments
  has_many :order_notes, dependent: :destroy
  has_many :order_discounts, dependent: :destroy
  has_many :discounts, through: :order_discounts
  has_many :order_taxes, dependent: :destroy
  has_many :taxes, through: :order_taxes
  has_many :order_refunds, dependent: :destroy
  has_many :refunds, through: :order_refunds
  has_many :order_analytics, dependent: :destroy

  # 驗證
  validates :order_number, presence: true, uniqueness: { scope: :store_id }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :subtotal_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :shipping_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, length: { is: 3 }

  # 回調
  before_validation :generate_order_number, on: :create
  before_save :calculate_totals
  after_create :create_order_analytics
  after_update :update_inventory_on_status_change
  after_update :send_status_notification

  # 搜尋
  searchkick word_start: [:order_number, :customer_name, :customer_email]

  # 列舉
  enum status: {
    pending: 0,
    confirmed: 1,
    processing: 2,
    shipped: 3,
    delivered: 4,
    completed: 5,
    cancelled: 6,
    refunded: 7,
    failed: 8
  }

  enum payment_status: {
    unpaid: 0,
    partially_paid: 1,
    paid: 2,
    partially_refunded: 3,
    refunded: 4,
    failed: 5
  }

  enum fulfillment_status: {
    unfulfilled: 0,
    partially_fulfilled: 1,
    fulfilled: 2,
    cancelled: 3
  }

  # 範圍
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :this_week, -> { where(created_at: Time.current.beginning_of_week..Time.current.end_of_week) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  scope :this_year, -> { where(created_at: Time.current.beginning_of_year..Time.current.end_of_year) }
  scope :completed, -> { where(status: :completed) }
  scope :pending_payment, -> { where(payment_status: [:unpaid, :partially_paid]) }
  scope :pending_fulfillment, -> { where(fulfillment_status: [:unfulfilled, :partially_fulfilled]) }
  scope :high_value, -> { where('total_amount >= ?', 10000) }
  scope :by_status, ->(status) { where(status: status) }

  # 方法
  def display_name
    "訂單 #{order_number}"
  end

  def customer_name
    user.full_name
  end

  def customer_email
    user.email
  end

  def customer_phone
    user.phone
  end

  def items_count
    order_items.sum(:quantity)
  end

  def unique_items_count
    order_items.count
  end

  def can_cancel?
    %w[pending confirmed processing].include?(status)
  end

  def can_refund?
    %w[paid partially_paid].include?(payment_status) && %w[shipped delivered completed].include?(status)
  end

  def can_ship?
    %w[confirmed processing].include?(status) && paid?
  end

  def can_mark_as_delivered?
    shipped?
  end

  def can_mark_as_completed?
    delivered?
  end

  def is_paid?
    payment_status == 'paid'
  end

  def is_fulfilled?
    fulfillment_status == 'fulfilled'
  end

  def is_completed?
    status == 'completed'
  end

  def is_cancelled?
    status == 'cancelled'
  end

  def is_refunded?
    status == 'refunded'
  end

  def total_paid
    payments.successful.sum(:amount)
  end

  def total_refunded
    refunds.approved.sum(:amount)
  end

  def outstanding_amount
    total_amount - total_paid + total_refunded
  end

  def is_fully_paid?
    outstanding_amount <= 0
  end

  def is_overpaid?
    outstanding_amount < 0
  end

  def total_shipped
    shipments.sum(:quantity)
  end

  def total_items
    order_items.sum(:quantity)
  end

  def is_fully_shipped?
    total_shipped >= total_items
  end

  def is_partially_shipped?
    total_shipped > 0 && total_shipped < total_items
  end

  def shipping_address_full
    shipping_address&.full_address
  end

  def billing_address_full
    billing_address&.full_address
  end

  def primary_payment_method
    payments.order(created_at: :desc).first&.payment_method
  end

  def primary_shipment
    shipments.order(created_at: :desc).first
  end

  def tracking_numbers
    shipments.pluck(:tracking_number).compact
  end

  def tracking_urls
    shipments.map(&:tracking_url).compact
  end

  def discount_codes
    order_discounts.map(&:discount_code).compact
  end

  def tax_breakdown
    order_taxes.group_by(&:tax_name).transform_values(&:sum)
  end

  def profit_margin
    return 0 if total_amount.zero?
    
    total_cost = order_items.sum('quantity * cost_price')
    ((total_amount - total_cost) / total_amount * 100).round(2)
  end

  def average_item_price
    return 0 if items_count.zero?
    (subtotal_amount / items_count).round(2)
  end

  def days_since_created
    (Time.current - created_at) / 1.day
  end

  def days_since_updated
    (Time.current - updated_at) / 1.day
  end

  def estimated_delivery_date
    return nil unless shipped_at
    shipped_at + 3.days
  end

  def is_overdue?
    return false unless estimated_delivery_date
    Time.current > estimated_delivery_date && !delivered?
  end

  def overdue_days
    return 0 unless is_overdue?
    (Time.current - estimated_delivery_date) / 1.day
  end

  def add_note(content, user = nil, note_type: 'general')
    order_notes.create!(
      content: content,
      user: user,
      note_type: note_type
    )
  end

  def add_payment(amount, payment_method, transaction_id = nil)
    payments.create!(
      amount: amount,
      payment_method: payment_method,
      transaction_id: transaction_id,
      status: 'successful'
    )
  end

  def add_shipment(tracking_number, carrier, quantity = nil)
    quantity ||= total_items - total_shipped
    
    shipments.create!(
      tracking_number: tracking_number,
      carrier: carrier,
      quantity: quantity,
      shipped_at: Time.current
    )
  end

  def apply_discount(discount_code, amount)
    discount = store.discounts.find_by(code: discount_code, is_active: true)
    return false unless discount && discount.is_valid?
    
    order_discounts.create!(
      discount: discount,
      amount: amount,
      discount_code: discount_code
    )
  end

  def calculate_totals
    self.subtotal_amount = order_items.sum('quantity * unit_price')
    self.tax_amount = order_taxes.sum(:amount)
    self.shipping_amount = order_shipments.sum(:shipping_cost)
    self.discount_amount = order_discounts.sum(:amount)
    
    self.total_amount = subtotal_amount + tax_amount + shipping_amount - discount_amount
  end

  def update_status(new_status, user = nil)
    old_status = status
    update!(status: new_status)
    
    add_note("訂單狀態從 #{old_status} 變更為 #{new_status}", user, note_type: 'status_change')
  end

  def update_payment_status(new_status, user = nil)
    old_status = payment_status
    update!(payment_status: new_status)
    
    add_note("付款狀態從 #{old_status} 變更為 #{new_status}", user, note_type: 'payment_change')
  end

  def update_fulfillment_status(new_status, user = nil)
    old_status = fulfillment_status
    update!(fulfillment_status: new_status)
    
    add_note("出貨狀態從 #{old_status} 變更為 #{new_status}", user, note_type: 'fulfillment_change')
  end

  def cancel_order(reason = nil, user = nil)
    return false unless can_cancel?
    
    update_status('cancelled', user)
    add_note("訂單已取消。原因: #{reason}", user, note_type: 'cancellation') if reason
    
    # 釋放庫存
    order_items.each do |item|
      item.product.release_inventory(item.quantity)
    end
    
    # 發送取消通知
    OrderMailer.cancelled(self).deliver_later
    
    true
  end

  def refund_order(amount, reason = nil, user = nil)
    return false unless can_refund?
    
    refunds.create!(
      amount: amount,
      reason: reason,
      user: user,
      status: 'approved'
    )
    
    add_note("退款 #{amount}。原因: #{reason}", user, note_type: 'refund') if reason
    
    # 更新付款狀態
    if total_refunded >= total_amount
      update_payment_status('refunded', user)
    else
      update_payment_status('partially_refunded', user)
    end
    
    # 發送退款通知
    OrderMailer.refunded(self).deliver_later
    
    true
  end

  def ship_order(tracking_number, carrier, user = nil)
    return false unless can_ship?
    
    add_shipment(tracking_number, carrier)
    update_status('shipped', user)
    update_fulfillment_status('fulfilled', user)
    
    add_note("訂單已出貨。追蹤號碼: #{tracking_number}, 運送商: #{carrier}", user, note_type: 'shipment')
    
    # 發送出貨通知
    OrderMailer.shipped(self).deliver_later
    
    true
  end

  def mark_as_delivered(user = nil)
    return false unless can_mark_as_delivered?
    
    update_status('delivered', user)
    add_note("訂單已送達", user, note_type: 'delivery')
    
    # 發送送達通知
    OrderMailer.delivered(self).deliver_later
    
    true
  end

  def mark_as_completed(user = nil)
    return false unless can_mark_as_completed?
    
    update_status('completed', user)
    add_note("訂單已完成", user, note_type: 'completion')
    
    # 發送完成通知
    OrderMailer.completed(self).deliver_later
    
    true
  end

  def duplicate
    new_order = dup
    new_order.order_number = nil
    new_order.status = :pending
    new_order.payment_status = :unpaid
    new_order.fulfillment_status = :unfulfilled
    new_order.total_amount = 0
    new_order.subtotal_amount = 0
    new_order.tax_amount = 0
    new_order.shipping_amount = 0
    new_order.discount_amount = 0
    new_order.save!
    
    # 複製訂單項目
    order_items.each do |item|
      new_order.order_items.create!(
        product: item.product,
        quantity: item.quantity,
        unit_price: item.unit_price,
        total_price: item.total_price
      )
    end
    
    new_order
  end

  private

  def generate_order_number
    return if order_number.present?
    
    prefix = store.slug.upcase[0..2]
    date = Time.current.strftime('%Y%m%d')
    counter = Order.where(store: store, created_at: Time.current.beginning_of_day..Time.current.end_of_day).count + 1
    
    self.order_number = "#{prefix}#{date}#{counter.to_s.rjust(4, '0')}"
  end

  def create_order_analytics
    order_analytics.create!(
      created_at: created_at,
      total_amount: total_amount,
      items_count: items_count
    )
  end

  def update_inventory_on_status_change
    return unless saved_change_to_status?
    
    case status
    when 'cancelled'
      # 釋放庫存
      order_items.each do |item|
        item.product.release_inventory(item.quantity)
      end
    when 'confirmed'
      # 預留庫存
      order_items.each do |item|
        item.product.reserve_inventory(item.quantity)
      end
    end
  end

  def send_status_notification
    return unless saved_change_to_status?
    
    case status
    when 'confirmed'
      OrderMailer.confirmed(self).deliver_later
    when 'shipped'
      OrderMailer.shipped(self).deliver_later
    when 'delivered'
      OrderMailer.delivered(self).deliver_later
    when 'completed'
      OrderMailer.completed(self).deliver_later
    when 'cancelled'
      OrderMailer.cancelled(self).deliver_later
    end
  end

  def search_data
    {
      order_number: order_number,
      customer_name: customer_name,
      customer_email: customer_email,
      status: status,
      payment_status: payment_status,
      fulfillment_status: fulfillment_status,
      total_amount: total_amount,
      currency: currency,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end 