require "test_helper"

class OrderAssociationsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "declares every order relationship bidirectionally" do
    assert_inverse Customer, :orders, Order, :customer
    assert_inverse Order, :order_items, OrderItem, :order
    assert_inverse Order, :order_payments, OrderPayment, :order
    assert_inverse Order, :order_reviews, OrderReview, :order
    assert_inverse Product, :order_items, OrderItem, :product
    assert_inverse Seller, :order_items, OrderItem, :seller
  end

  private

  def assert_inverse(owner_class, collection_name, member_class, owner_name)
    collection = owner_class.reflect_on_association(collection_name)
    owner = member_class.reflect_on_association(owner_name)

    assert_equal member_class, collection.klass
    assert_equal owner_class, owner.klass
    assert_equal owner, collection.inverse_of
    assert_equal collection, owner.inverse_of
  end
end
