class Lottery < ActiveRecord::Base
  self.table_name = 'lotteries'

  belongs_to :topic
  belongs_to :user, foreign_key: :created_by_id

  enum status: { running: 0, finished: 1, cancelled: 2 }
  enum draw_type: { by_time: 1, by_reply: 2 }

  def participating_user_count
    Post.where(topic_id: self.topic_id)
        .where("post_number > 1")
        .where.not(user_id: self.created_by_id)
        .distinct.count(:user_id)
  end
end
