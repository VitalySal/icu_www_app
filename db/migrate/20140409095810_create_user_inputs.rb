class CreateUserInputs < ActiveRecord::Migration[7.0]
  def change
    create_table :user_inputs do |t|
      t.integer  :fee_id
      t.string   :type, limit: 40
      t.string   :label, limit: 100
      t.boolean  :required, default: true
      t.integer  :max_length, limit: 2
      t.decimal  :min_amount, precision: 6, scale: 2, default: 1.0
      t.string   :date_constraint, limit: 30, default: "none"
    end
  end
end
