class OrderSerializer < ActiveModel::Serializer
  attributes :id, :order_number, :status, :payment_status, :fulfillment_status,
             :total_amount, :subtotal_amount, :tax_amount, :shipping_amount, :discount_amount,
             :currency, :items_count, :unique_items_count, :notes,
             :created_at, :updated_at, :shipped_at, :delivered_at, :completed_at

  belongs_to :user, serializer: UserSerializer
  belongs_to :store, serializer: StoreSerializer
  has_many :order_items, serializer: OrderItemSerializer
  has_many :payments, serializer: PaymentSerializer
  has_many :shipments, serializer: ShipmentSerializer
  has_many :order_notes, serializer: OrderNoteSerializer

  def items_count
    object.items_count
  end

  def unique_items_count
    object.unique_items_count
  end

  def status
    {
      value: object.status,
      label: object.status.humanize,
      color: status_color(object.status)
    }
  end

  def payment_status
    {
      value: object.payment_status,
      label: object.payment_status.humanize,
      color: payment_status_color(object.payment_status)
    }
  end

  def fulfillment_status
    {
      value: object.fulfillment_status,
      label: object.fulfillment_status.humanize,
      color: fulfillment_status_color(object.fulfillment_status)
    }
  end

  def can_cancel?
    object.can_cancel?
  end

  def can_refund?
    object.can_refund?
  end

  def can_ship?
    object.can_ship?
  end

  def can_mark_as_delivered?
    object.can_mark_as_delivered?
  end

  def can_mark_as_completed?
    object.can_mark_as_completed?
  end

  def is_paid?
    object.is_paid?
  end

  def is_fulfilled?
    object.is_fulfilled?
  end

  def is_completed?
    object.is_completed?
  end

  def is_cancelled?
    object.is_cancelled?
  end

  def is_refunded?
    object.is_refunded?
  end

  def total_paid
    object.total_paid
  end

  def total_refunded
    object.total_refunded
  end

  def outstanding_amount
    object.outstanding_amount
  end

  def is_fully_paid?
    object.is_fully_paid?
  end

  def is_overpaid?
    object.is_overpaid?
  end

  def total_shipped
    object.total_shipped
  end

  def total_items
    object.total_items
  end

  def is_fully_shipped?
    object.is_fully_shipped?
  end

  def is_partially_shipped?
    object.is_partially_shipped?
  end

  def tracking_numbers
    object.tracking_numbers
  end

  def tracking_urls
    object.tracking_urls
  end

  def discount_codes
    object.discount_codes
  end

  def tax_breakdown
    object.tax_breakdown
  end

  def profit_margin
    object.profit_margin
  end

  def average_item_price
    object.average_item_price
  end

  def days_since_created
    object.days_since_created
  end

  def days_since_updated
    object.days_since_updated
  end

  def estimated_delivery_date
    object.estimated_delivery_date
  end

  def is_overdue?
    object.is_overdue?
  end

  def overdue_days
    object.overdue_days
  end

  private

  def status_color(status)
    case status
    when 'pending'
      '#ffc107'
    when 'confirmed'
      '#17a2b8'
    when 'processing'
      '#007bff'
    when 'shipped'
      '#28a745'
    when 'delivered'
      '#6f42c1'
    when 'completed'
      '#28a745'
    when 'cancelled'
      '#dc3545'
    when 'refunded'
      '#fd7e14'
    when 'failed'
      '#6c757d'
    else
      '#6c757d'
    end
  end

  def payment_status_color(status)
    case status
    when 'unpaid'
      '#dc3545'
    when 'partially_paid'
      '#ffc107'
    when 'paid'
      '#28a745'
    when 'partially_refunded'
      '#fd7e14'
    when 'refunded'
      '#6f42c1'
    when 'failed'
      '#6c757d'
    else
      '#6c757d'
    end
  end

  def fulfillment_status_color(status)
    case status
    when 'unfulfilled'
      '#dc3545'
    when 'partially_fulfilled'
      '#ffc107'
    when 'fulfilled'
      '#28a745'
    when 'cancelled'
      '#6c757d'
    else
      '#6c757d'
    end
  end
end 