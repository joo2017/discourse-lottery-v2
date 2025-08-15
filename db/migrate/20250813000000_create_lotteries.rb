class CreateLotteries < ActiveRecord::Migration[6.1]
  def change
    create_table :lotteries do |t|
      t.integer :topic_id, null: false
      t.integer :post_id, null: false
      t.integer :created_by_id, null: false
      t.string :name, null: false
      t.text :prize, null: false
      t.integer :winner_count, null: false, default: 1
      t.integer :draw_type, null: false
      t.timestamp :draw_at
      t.integer :draw_reply_count
      t.string :specific_floors
      t.text :description
      t.text :extra_info
      t.integer :status, null: false, default: 0
      t.jsonb :winner_data
      t.timestamps
    end

    add_index :lotteries, :topic_id, unique: true
    add_index :lotteries, :status
    add_index :lotteries, :created_by_id
    add_index :lotteries, :draw_at
    add_index :lotteries, [:status, :draw_at]
    add_index :lotteries, [:status, :draw_reply_count]
  end
end
