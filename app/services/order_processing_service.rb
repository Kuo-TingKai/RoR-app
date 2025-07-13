class OrderProcessingService
  include ActiveModel::Validations

  attr_reader :order, :user, :errors

  validates :order, presence: true
  validates :user, presence: true

  def initialize(order, user = nil)
    @order = order
    @user = user
    @errors = []
  end

  def process
    return false unless valid?

    ActiveRecord::Base.transaction do
      validate_order_items
      validate_inventory
      validate_payment_method
      calculate_totals
      apply_discounts
      apply_taxes
      apply_shipping
      finalize_order
      send_notifications
      
      true
    rescue StandardError => e
      @errors << e.message
      false
    end
  end

  def confirm
    return false unless valid?
    return false unless order.pending?

    ActiveRecord::Base.transaction do
      validate_inventory_availability
      reserve_inventory
      update_order_status(:confirmed)
      send_confirmation_notifications
      
      true
    rescue StandardError => e
      @errors << e.message
      false
    end
  end

  def cancel(reason = nil)
    return false unless valid?
    return false unless order.can_cancel?

    ActiveRecord::Base.transaction do
      release_inventory
      update_order_status(:cancelled)
      add_cancellation_note(reason)
      send_cancellation_notifications
      
      true
    rescue StandardError => e
      @errors << e.message
      false
    end
  end

  def refund(amount, reason = nil)
    return false unless valid?
    return false unless order.can_refund?
    return false unless amount > 0 && amount <= order.total_amount

    ActiveRecord::Base.transaction do
      process_refund(amount, reason)
      update_payment_status
      add_refund_note(amount, reason)
      send_refund_notifications
      
      true
    rescue StandardError => e
      @errors << e.message
      false
    end
  end

  def ship(tracking_number, carrier)
    return false unless valid?
    return false unless order.can_ship?

    ActiveRecord::Base.transaction do
      create_shipment(tracking_number, carrier)
      update_order_status(:shipped)
      update_fulfillment_status(:fulfilled)
      add_shipment_note(tracking_number, carrier)
      send_shipment_notifications
      
      true
    rescue StandardError => e
      @errors << e.message
      false
    end
  end

  private

  def validate_order_items
    return if order.order_items.any?
    raise "訂單必須包含至少一個商品"
  end

  def validate_inventory
    order.order_items.each do |item|
      next unless item.product.track_inventory?
      
      available = item.product.available_quantity
      if available < item.quantity
        raise "商品 #{item.product.name} 庫存不足。需要: #{item.quantity}, 可用: #{available}"
      end
    end
  end

  def validate_inventory_availability
    order.order_items.each do |item|
      next unless item.product.track_inventory?
      
      available = item.product.available_quantity
      if available < item.quantity
        raise "商品 #{item.product.name} 庫存不足。需要: #{item.quantity}, 可用: #{available}"
      end
    end
  end

  def validate_payment_method
    return if order.payment_methods.any?
    raise "訂單必須選擇付款方式"
  end

  def calculate_totals
    subtotal = order.order_items.sum('quantity * unit_price')
    order.update!(
      subtotal_amount: subtotal,
      total_amount: subtotal
    )
  end

  def apply_discounts
    return unless order.discount_codes.any?
    
    total_discount = 0
    order.discount_codes.each do |code|
      discount = order.store.discounts.find_by(code: code, is_active: true)
      next unless discount&.is_valid?
      
      discount_amount = calculate_discount_amount(discount)
      order.order_discounts.create!(
        discount: discount,
        amount: discount_amount,
        discount_code: code
      )
      total_discount += discount_amount
    end
    
    order.update!(discount_amount: total_discount)
    recalculate_total
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

  def apply_taxes
    tax_rate = order.store.tax_rate
    return if tax_rate.zero?
    
    taxable_amount = order.subtotal_amount - order.discount_amount
    tax_amount = (taxable_amount * tax_rate / 100).round(2)
    
    order.order_taxes.create!(
      tax_name: '營業稅',
      rate: tax_rate,
      amount: tax_amount
    )
    
    order.update!(tax_amount: tax_amount)
    recalculate_total
  end

  def apply_shipping
    shipping_method = order.shipping_methods.first
    return unless shipping_method
    
    shipping_cost = calculate_shipping_cost(shipping_method)
    order.update!(shipping_amount: shipping_cost)
    recalculate_total
  end

  def calculate_shipping_cost(shipping_method)
    case shipping_method.calculation_method
    when 'fixed'
      shipping_method.base_cost
    when 'weight_based'
      total_weight = order.order_items.sum { |item| item.product.shipping_weight * item.quantity }
      shipping_method.base_cost + (total_weight * shipping_method.weight_rate)
    when 'price_based'
      if order.subtotal_amount >= shipping_method.free_shipping_threshold
        0
      else
        shipping_method.base_cost
      end
    else
      0
    end
  end

  def recalculate_total
    total = order.subtotal_amount + order.tax_amount + order.shipping_amount - order.discount_amount
    order.update!(total_amount: total)
  end

  def finalize_order
    order.update!(
      status: :pending,
      payment_status: :unpaid,
      fulfillment_status: :unfulfilled
    )
  end

  def reserve_inventory
    order.order_items.each do |item|
      next unless item.product.track_inventory?
      item.product.reserve_inventory(item.quantity)
    end
  end

  def release_inventory
    order.order_items.each do |item|
      next unless item.product.track_inventory?
      item.product.release_inventory(item.quantity)
    end
  end

  def update_order_status(status)
    order.update!(status: status)
  end

  def update_payment_status
    if order.total_refunded >= order.total_amount
      order.update!(payment_status: :refunded)
    elsif order.total_refunded > 0
      order.update!(payment_status: :partially_refunded)
    end
  end

  def update_fulfillment_status(status)
    order.update!(fulfillment_status: status)
  end

  def process_refund(amount, reason)
    order.refunds.create!(
      amount: amount,
      reason: reason,
      user: user,
      status: 'approved'
    )
  end

  def create_shipment(tracking_number, carrier)
    order.shipments.create!(
      tracking_number: tracking_number,
      carrier: carrier,
      quantity: order.total_items,
      shipped_at: Time.current
    )
  end

  def add_cancellation_note(reason)
    order.add_note("訂單已取消。原因: #{reason}", user, 'cancellation')
  end

  def add_refund_note(amount, reason)
    order.add_note("退款 #{amount}。原因: #{reason}", user, 'refund')
  end

  def add_shipment_note(tracking_number, carrier)
    order.add_note("訂單已出貨。追蹤號碼: #{tracking_number}, 運送商: #{carrier}", user, 'shipment')
  end

  def send_notifications
    OrderMailer.created(order).deliver_later
    order.store.send_notification("新訂單 #{order.order_number} 已建立", 'info')
  end

  def send_confirmation_notifications
    OrderMailer.confirmed(order).deliver_later
    order.store.send_notification("訂單 #{order.order_number} 已確認", 'info')
  end

  def send_cancellation_notifications
    OrderMailer.cancelled(order).deliver_later
    order.store.send_notification("訂單 #{order.order_number} 已取消", 'warning')
  end

  def send_refund_notifications
    OrderMailer.refunded(order).deliver_later
    order.store.send_notification("訂單 #{order.order_number} 已退款", 'info')
  end

  def send_shipment_notifications
    OrderMailer.shipped(order).deliver_later
    order.store.send_notification("訂單 #{order.order_number} 已出貨", 'info')
  end
end 