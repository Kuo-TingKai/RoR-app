class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :confirmable, :lockable

  # 關聯
  has_many :stores, dependent: :destroy
  has_many :orders, through: :stores
  has_many :addresses, dependent: :destroy
  has_many :payment_methods, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles

  # 驗證
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, format: { with: /\A\+?[\d\s\-\(\)]+\z/ }, allow_blank: true
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }

  # 回調
  before_create :set_default_role
  after_create :send_welcome_email

  # 搜尋
  searchkick word_start: [:email, :first_name, :last_name]

  # 列舉
  enum status: { active: 0, inactive: 1, suspended: 2 }
  enum gender: { not_specified: 0, male: 1, female: 2, other: 3 }

  # 範圍
  scope :active, -> { where(status: :active) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_stores, -> { joins(:stores) }

  # 方法
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def display_name
    full_name.presence || email
  end

  def admin?
    roles.exists?(name: 'admin')
  end

  def store_owner?
    roles.exists?(name: 'store_owner')
  end

  def customer?
    roles.exists?(name: 'customer')
  end

  def has_role?(role_name)
    roles.exists?(name: role_name)
  end

  def primary_address
    addresses.find_by(is_primary: true) || addresses.first
  end

  def default_payment_method
    payment_methods.find_by(is_default: true) || payment_methods.first
  end

  def total_orders_count
    orders.count
  end

  def total_spent
    orders.completed.sum(:total_amount)
  end

  def average_order_value
    return 0 if total_orders_count.zero?
    total_spent / total_orders_count
  end

  def last_order_date
    orders.order(created_at: :desc).first&.created_at
  end

  def days_since_last_order
    return nil unless last_order_date
    (Time.current - last_order_date) / 1.day
  end

  def lifetime_value
    total_spent
  end

  def customer_segment
    case lifetime_value
    when 0..1000
      'bronze'
    when 1001..5000
      'silver'
    when 5001..10000
      'gold'
    else
      'platinum'
    end
  end

  def send_password_reset_email
    generate_reset_password_token!
    UserMailer.password_reset(self).deliver_now
  end

  def send_welcome_email
    UserMailer.welcome(self).deliver_later
  end

  def update_last_login
    update_column(:last_sign_in_at, Time.current)
  end

  def generate_api_token
    update_column(:api_token, SecureRandom.hex(32))
  end

  def revoke_api_token
    update_column(:api_token, nil)
  end

  private

  def set_default_role
    self.roles << Role.find_by(name: 'customer') if roles.empty?
  end

  def search_data
    {
      email: email,
      first_name: first_name,
      last_name: last_name,
      full_name: full_name,
      phone: phone,
      status: status,
      created_at: created_at,
      last_sign_in_at: last_sign_in_at
    }
  end
end 