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
      t.timestamp :draw_at, null: false
      t.string :specific_floors
      t.text :description
      t.text :extra_info
      t.integer :status, null: false, default: 0
      t.integer :min_participants_user, null: false, default: 1
      t.integer :insufficient_participants_action, null: false, default: 0 # 0: 继续开奖, 1: 取消
      t.text :winner_data
      t.timestamps null: false
    end

    add_index :lotteries, :topic_id, unique: true
    add_index :lotteries, :status
    add_index :lotteries, :created_by_id
    add_index :lotteries, [:status, :draw_at]
  end
end
