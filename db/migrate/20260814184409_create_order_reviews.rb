class CreateOrderReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :order_reviews do |t|
      t.references :order, null: false, foreign_key: true

      t.string :review_id, null: false, limit: 32
      t.integer :score, null: false
      t.string :comment_title, limit: 26
      t.text :comment_message
      t.datetime :creation_at, null: false
      t.datetime :answer_at, null: false

      t.timestamps
    end

    add_index :order_reviews, :review_id
  end
end
