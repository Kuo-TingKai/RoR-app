require 'rails_helper'

RSpec.describe Order, type: :model do
  let(:user) { create(:user) }
  let(:store) { create(:store, user: user) }
  let(:product) { create(:product, store: store) }
  let(:order) { create(:order, store: store, user: user) }

  describe 'validations' do
    it { should validate_presence_of(:order_number) }
    it { should validate_presence_of(:total_amount) }
    it { should validate_presence_of(:subtotal_amount) }
    it { should validate_presence_of(:currency) }
    
    it { should validate_numericality_of(:total_amount).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:subtotal_amount).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:tax_amount).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:shipping_amount).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:discount_amount).is_greater_than_or_equal_to(0) }
    
    it { should validate_length_of(:currency).is_equal_to(3) }
  end

  describe 'associations' do
    it { should belong_to(:store) }
    it { should belong_to(:user) }
    it { should belong_to(:billing_address).class_name('Address').optional }
    it { should belong_to(:shipping_address).class_name('Address').optional }
    
    it { should have_many(:order_items).dependent(:destroy) }
    it { should have_many(:products).through(:order_items) }
    it { should have_many(:order_payments).dependent(:destroy) }
    it { should have_many(:payments).through(:order_payments) }
    it { should have_many(:order_shipments).dependent(:destroy) }
    it { should have_many(:shipments).through(:order_shipments) }
    it { should have_many(:order_notes).dependent(:destroy) }
    it { should have_many(:order_discounts).dependent(:destroy) }
    it { should have_many(:discounts).through(:order_discounts) }
    it { should have_many(:order_taxes).dependent(:destroy) }
    it { should have_many(:taxes).through(:order_taxes) }
    it { should have_many(:order_refunds).dependent(:destroy) }
    it { should have_many(:refunds).through(:order_refunds) }
    it { should have_many(:order_analytics).dependent(:destroy) }
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(described_class.statuses) }
    it { should define_enum_for(:payment_status).with_values(described_class.payment_statuses) }
    it { should define_enum_for(:fulfillment_status).with_values(described_class.fulfillment_statuses) }
  end

  describe 'scopes' do
    let!(:order1) { create(:order, store: store, created_at: 1.day.ago) }
    let!(:order2) { create(:order, store: store, created_at: 2.days.ago) }
    let!(:order3) { create(:order, store: store, created_at: 3.days.ago) }

    describe '.recent' do
      it 'returns orders ordered by created_at desc' do
        expect(Order.recent).to eq([order1, order2, order3])
      end
    end

    describe '.today' do
      it 'returns orders created today' do
        expect(Order.today).to include(order1)
        expect(Order.today).not_to include(order2, order3)
      end
    end

    describe '.completed' do
      let!(:completed_order) { create(:order, store: store, status: :completed) }
      
      it 'returns only completed orders' do
        expect(Order.completed).to include(completed_order)
        expect(Order.completed).not_to include(order1, order2, order3)
      end
    end

    describe '.high_value' do
      let!(:high_value_order) { create(:order, store: store, total_amount: 15000) }
      
      it 'returns orders with total_amount >= 10000' do
        expect(Order.high_value).to include(high_value_order)
        expect(Order.high_value).not_to include(order1, order2, order3)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates order number on create' do
        new_order = build(:order, store: store, user: user, order_number: nil)
        new_order.valid?
        expect(new_order.order_number).to be_present
      end
    end

    describe 'before_save' do
      it 'calculates totals before save' do
        order_item = create(:order_item, order: order, product: product, quantity: 2, unit_price: 100)
        order.calculate_totals
        expect(order.subtotal_amount).to eq(200)
      end
    end
  end

  describe 'instance methods' do
    let(:order_item) { create(:order_item, order: order, product: product, quantity: 2, unit_price: 100) }

    describe '#customer_name' do
      it 'returns user full name' do
        expect(order.customer_name).to eq(user.full_name)
      end
    end

    describe '#customer_email' do
      it 'returns user email' do
        expect(order.customer_email).to eq(user.email)
      end
    end

    describe '#items_count' do
      it 'returns total quantity of order items' do
        order_item
        expect(order.items_count).to eq(2)
      end
    end

    describe '#unique_items_count' do
      it 'returns count of unique order items' do
        order_item
        expect(order.unique_items_count).to eq(1)
      end
    end

    describe '#can_cancel?' do
      it 'returns true for pending orders' do
        expect(order.can_cancel?).to be true
      end

      it 'returns false for completed orders' do
        order.update!(status: :completed)
        expect(order.can_cancel?).to be false
      end
    end

    describe '#can_refund?' do
      it 'returns false for unpaid orders' do
        expect(order.can_refund?).to be false
      end

      it 'returns true for paid and shipped orders' do
        order.update!(payment_status: :paid, status: :shipped)
        expect(order.can_refund?).to be true
      end
    end

    describe '#is_paid?' do
      it 'returns true when payment_status is paid' do
        order.update!(payment_status: :paid)
        expect(order.is_paid?).to be true
      end

      it 'returns false when payment_status is unpaid' do
        expect(order.is_paid?).to be false
      end
    end

    describe '#total_paid' do
      let!(:payment) { create(:payment, order: order, amount: 100, status: 'successful') }

      it 'returns sum of successful payments' do
        expect(order.total_paid).to eq(100)
      end
    end

    describe '#outstanding_amount' do
      let!(:payment) { create(:payment, order: order, amount: 50, status: 'successful') }

      it 'returns outstanding amount' do
        order.update!(total_amount: 100)
        expect(order.outstanding_amount).to eq(50)
      end
    end

    describe '#is_fully_paid?' do
      it 'returns true when fully paid' do
        order.update!(total_amount: 100)
        create(:payment, order: order, amount: 100, status: 'successful')
        expect(order.is_fully_paid?).to be true
      end

      it 'returns false when not fully paid' do
        order.update!(total_amount: 100)
        create(:payment, order: order, amount: 50, status: 'successful')
        expect(order.is_fully_paid?).to be false
      end
    end

    describe '#profit_margin' do
      it 'calculates profit margin correctly' do
        order.update!(total_amount: 100)
        order_item.update!(cost_price: 60)
        expect(order.profit_margin).to eq(40.0)
      end

      it 'returns 0 when total_amount is 0' do
        order.update!(total_amount: 0)
        expect(order.profit_margin).to eq(0)
      end
    end

    describe '#average_item_price' do
      it 'calculates average item price correctly' do
        order_item
        order.update!(subtotal_amount: 200)
        expect(order.average_item_price).to eq(100)
      end

      it 'returns 0 when no items' do
        expect(order.average_item_price).to eq(0)
      end
    end

    describe '#days_since_created' do
      it 'returns days since order was created' do
        order.update!(created_at: 5.days.ago)
        expect(order.days_since_created).to be_within(0.1).of(5)
      end
    end

    describe '#estimated_delivery_date' do
      it 'returns estimated delivery date' do
        order.update!(shipped_at: 1.day.ago)
        expect(order.estimated_delivery_date).to eq(order.shipped_at + 3.days)
      end

      it 'returns nil when not shipped' do
        expect(order.estimated_delivery_date).to be_nil
      end
    end

    describe '#is_overdue?' do
      it 'returns true when overdue' do
        order.update!(shipped_at: 5.days.ago)
        expect(order.is_overdue?).to be true
      end

      it 'returns false when not overdue' do
        order.update!(shipped_at: 1.day.ago)
        expect(order.is_overdue?).to be false
      end
    end

    describe '#add_note' do
      it 'creates an order note' do
        expect {
          order.add_note('Test note', user, 'general')
        }.to change(OrderNote, :count).by(1)
      end
    end

    describe '#add_payment' do
      it 'creates a payment' do
        expect {
          order.add_payment(100, 'credit_card', 'txn_123')
        }.to change(Payment, :count).by(1)
      end
    end

    describe '#add_shipment' do
      it 'creates a shipment' do
        expect {
          order.add_shipment('TRK123', 'FedEx')
        }.to change(Shipment, :count).by(1)
      end
    end

    describe '#cancel_order' do
      it 'cancels the order successfully' do
        expect(order.cancel_order('Customer request', user)).to be true
        expect(order.reload.status).to eq('cancelled')
      end

      it 'returns false for completed orders' do
        order.update!(status: :completed)
        expect(order.cancel_order('Test', user)).to be false
      end
    end

    describe '#refund_order' do
      before do
        order.update!(payment_status: :paid, status: :shipped)
      end

      it 'refunds the order successfully' do
        expect(order.refund_order(50, 'Customer request', user)).to be true
        expect(order.reload.payment_status).to eq('partially_refunded')
      end

      it 'returns false for invalid amount' do
        expect(order.refund_order(0, 'Test', user)).to be false
      end
    end

    describe '#ship_order' do
      before do
        order.update!(payment_status: :paid, status: :confirmed)
      end

      it 'ships the order successfully' do
        expect(order.ship_order('TRK123', 'FedEx', user)).to be true
        expect(order.reload.status).to eq('shipped')
      end

      it 'returns false for unpaid orders' do
        order.update!(payment_status: :unpaid)
        expect(order.ship_order('TRK123', 'FedEx', user)).to be false
      end
    end

    describe '#mark_as_delivered' do
      before do
        order.update!(status: :shipped)
      end

      it 'marks order as delivered' do
        expect(order.mark_as_delivered(user)).to be true
        expect(order.reload.status).to eq('delivered')
      end

      it 'returns false for non-shipped orders' do
        order.update!(status: :pending)
        expect(order.mark_as_delivered(user)).to be false
      end
    end

    describe '#mark_as_completed' do
      before do
        order.update!(status: :delivered)
      end

      it 'marks order as completed' do
        expect(order.mark_as_completed(user)).to be true
        expect(order.reload.status).to eq('completed')
      end

      it 'returns false for non-delivered orders' do
        order.update!(status: :shipped)
        expect(order.mark_as_completed(user)).to be false
      end
    end
  end

  describe 'private methods' do
    describe '#generate_order_number' do
      it 'generates unique order number' do
        new_order = build(:order, store: store, user: user, order_number: nil)
        new_order.send(:generate_order_number)
        expect(new_order.order_number).to match(/#{store.slug.upcase[0..2]}\d{12}/)
      end
    end

    describe '#calculate_totals' do
      it 'calculates totals correctly' do
        create(:order_item, order: order, product: product, quantity: 2, unit_price: 100)
        create(:order_tax, order: order, amount: 10)
        create(:order_discount, order: order, amount: 20)
        
        order.send(:calculate_totals)
        
        expect(order.subtotal_amount).to eq(200)
        expect(order.tax_amount).to eq(10)
        expect(order.discount_amount).to eq(20)
        expect(order.total_amount).to eq(190)
      end
    end
  end
end 