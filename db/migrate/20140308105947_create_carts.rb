class CreateCarts < ActiveRecord::Migration[7.0]
  def change
    create_table :carts do |t|
      t.string   :status, limit: 20, default: "unpaid"
      t.decimal  :total, :original_total, precision: 9, scale: 2
      t.string   :payment_method, limit: 20
      t.string   :payment_ref, :confirmation_email, limit: 50
      t.string   :confirmation_error
      t.text     :confirmation_text
      t.boolean  :confirmation_sent, default: false
      t.string   :payment_name, limit: 100
      t.integer  :user_id
      t.datetime :payment_completed

      t.timestamps
    end
  end
end
