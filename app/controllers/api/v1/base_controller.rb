class Api::V1::BaseController < ApplicationController
  include Pundit::Authorization
  
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!
  before_action :set_paper_trail_whodunnit
  
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ActionController::ParameterMissing, with: :bad_request
  rescue_from StandardError, with: :internal_server_error

  private

  def authenticate_user!
    token = extract_token_from_header
    
    if token.blank?
      render json: { error: '缺少認證令牌' }, status: :unauthorized
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.credentials.secret_key_base, true, { algorithm: 'HS256' })
      user_id = payload[0]['user_id']
      @current_user = User.find(user_id)
      
      # 更新最後登入時間
      @current_user.update_last_login
    rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
      render json: { error: '無效的認證令牌' }, status: :unauthorized
    end
  end

  def current_user
    @current_user
  end

  def extract_token_from_header
    request.headers['Authorization']&.split(' ')&.last
  end

  def not_found(exception)
    render json: { error: '資源不存在' }, status: :not_found
  end

  def unprocessable_entity(exception)
    render json: { 
      error: '資料驗證失敗',
      details: exception.record.errors.full_messages 
    }, status: :unprocessable_entity
  end

  def forbidden(exception)
    render json: { error: '權限不足' }, status: :forbidden
  end

  def bad_request(exception)
    render json: { error: '請求參數錯誤' }, status: :bad_request
  end

  def internal_server_error(exception)
    Rails.logger.error "API Error: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")
    
    render json: { error: '伺服器內部錯誤' }, status: :internal_server_error
  end

  def paginate(collection)
    collection.page(params[:page]).per(params[:per_page] || 20)
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value,
      has_next: collection.next_page.present?,
      has_prev: collection.prev_page.present?
    }
  end

  def cache_key_with_version(key)
    "#{key}/#{Rails.cache.version}"
  end

  def cache_for(duration = 1.hour)
    Rails.cache.fetch(cache_key_with_version(request.fullpath), expires_in: duration) do
      yield
    end
  end

  def rate_limit_exceeded?
    key = "rate_limit:#{current_user.id}:#{request.path}"
    count = Rails.cache.read(key) || 0
    
    if count >= 100 # 每小時最多 100 次請求
      true
    else
      Rails.cache.write(key, count + 1, expires_in: 1.hour)
      false
    end
  end

  def check_rate_limit!
    if rate_limit_exceeded?
      render json: { error: '請求頻率過高，請稍後再試' }, status: :too_many_requests
    end
  end

  def log_api_request
    Rails.logger.info "API Request: #{request.method} #{request.path} - User: #{current_user.id} - IP: #{request.remote_ip}"
  end

  def log_api_response(status)
    Rails.logger.info "API Response: #{request.method} #{request.path} - Status: #{status}"
  end
end 