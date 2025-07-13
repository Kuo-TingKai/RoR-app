class Api::V1::OrdersController < Api::V1::BaseController
  before_action :authenticate_user!
  before_action :set_store, only: [:index, :create]
  before_action :set_order, only: [:show, :update, :destroy, :cancel, :confirm, :ship, :deliver, :complete]
  before_action :authorize_order_access!, only: [:show, :update, :destroy, :cancel, :confirm, :ship, :deliver, :complete]

  # GET /api/v1/stores/:store_id/orders
  def index
    @orders = policy_scope(Order)
              .where(store: @store)
              .includes(:user, :order_items, :products, :payments, :shipments)
              .order(created_at: :desc)
              .page(params[:page])
              .per(params[:per_page] || 20)

    render json: {
      orders: OrderSerializer.new(@orders).serializable_hash,
      pagination: pagination_meta(@orders)
    }
  end

  # GET /api/v1/stores/:store_id/orders/:id
  def show
    render json: OrderDetailSerializer.new(@order).serializable_hash
  end

  # POST /api/v1/stores/:store_id/orders
  def create
    @order_form = OrderForm.new(order_params.merge(store_id: @store.id, user_id: current_user.id))
    
    if @order_form.save
      @order = @order_form.order
      render json: OrderSerializer.new(@order).serializable_hash, status: :created
    else
      render json: { errors: @order_form.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/stores/:store_id/orders/:id
  def update
    @order_form = OrderForm.new(order_params.merge(store_id: @store.id, user_id: current_user.id))
    @order_form.order = @order
    
    if @order_form.update(order_params)
      render json: OrderSerializer.new(@order).serializable_hash
    else
      render json: { errors: @order_form.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/stores/:store_id/orders/:id
  def destroy
    if @order.destroy
      head :no_content
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/stores/:store_id/orders/:id/cancel
  def cancel
    service = OrderProcessingService.new(@order, current_user)
    
    if service.cancel(params[:reason])
      render json: OrderSerializer.new(@order.reload).serializable_hash
    else
      render json: { errors: service.errors }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/stores/:store_id/orders/:id/confirm
  def confirm
    service = OrderProcessingService.new(@order, current_user)
    
    if service.confirm
      render json: OrderSerializer.new(@order.reload).serializable_hash
    else
      render json: { errors: service.errors }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/stores/:store_id/orders/:id/ship
  def ship
    service = OrderProcessingService.new(@order, current_user)
    
    if service.ship(params[:tracking_number], params[:carrier])
      render json: OrderSerializer.new(@order.reload).serializable_hash
    else
      render json: { errors: service.errors }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/stores/:store_id/orders/:id/deliver
  def deliver
    if @order.mark_as_delivered(current_user)
      render json: OrderSerializer.new(@order.reload).serializable_hash
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/stores/:store_id/orders/:id/complete
  def complete
    if @order.mark_as_completed(current_user)
      render json: OrderSerializer.new(@order.reload).serializable_hash
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/stores/:store_id/orders/analytics
  def analytics
    authorize! :read, Order
    
    analytics_data = OrderAnalyticsService.new(@store).generate
    
    render json: {
      total_orders: analytics_data[:total_orders],
      total_revenue: analytics_data[:total_revenue],
      average_order_value: analytics_data[:average_order_value],
      orders_by_status: analytics_data[:orders_by_status],
      revenue_by_period: analytics_data[:revenue_by_period],
      top_products: analytics_data[:top_products],
      customer_segments: analytics_data[:customer_segments]
    }
  end

  # GET /api/v1/stores/:store_id/orders/export
  def export
    authorize! :read, Order
    
    format = params[:format] || 'csv'
    
    case format
    when 'csv'
      send_data OrderExportService.new(@store).to_csv, 
                filename: "orders_#{Time.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv'
    when 'xlsx'
      send_data OrderExportService.new(@store).to_xlsx, 
                filename: "orders_#{Time.current.strftime('%Y%m%d')}.xlsx",
                type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    else
      render json: { error: '不支援的匯出格式' }, status: :bad_request
    end
  end

  private

  def set_store
    @store = Store.find_by!(slug: params[:store_id])
  end

  def set_order
    @order = Order.find(params[:id])
  end

  def authorize_order_access!
    authorize! :manage, @order
  end

  def order_params
    params.require(:order).permit(
      :billing_address_id,
      :shipping_address_id,
      :payment_method_id,
      :shipping_method_id,
      :notes,
      :currency,
      discount_codes: [],
      order_items_attributes: [
        :product_id,
        :quantity
      ]
    )
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value
    }
  end
end 