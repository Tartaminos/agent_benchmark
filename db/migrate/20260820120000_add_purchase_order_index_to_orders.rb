class AddPurchaseOrderIndexToOrders < ActiveRecord::Migration[8.1]
  def change
    add_index :orders, %i[purchase_at order_id]
  end
end
