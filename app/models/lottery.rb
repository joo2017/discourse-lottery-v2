class Lottery < ActiveRecord::Base
  self.table_name = 'lotteries'

  belongs_to :topic
  belongs_to :user, foreign_key: :created_by_id

  # 改进：添加了 cancelled 状态
  enum status: { running: 0, finished: 1, cancelled: 2 }
  enum draw_type: { by_time: 1, by_reply: 2 }

  # 改进：使用缓存优化参与人数统计
  def participating_user_count
    cache_duration = SiteSetting.lottery_v2_cache_duration.seconds
    Rails.cache.fetch("lottery_#{id}_participants", expires_in: cache_duration) do
      Post.where(topic_id: self.topic_id)
          .where("post_number > 1")
          .where.not(user_id: self.created_by_id)
          .distinct
          .count(:user_id)
    end
  end

  # 改进：添加方法获取有效参与者（带用户信息），用于解决 N+1 问题
  def valid_participants_with_user
    Post.includes(:user)
        .where(topic_id: self.topic_id)
        .where("post_number > 1")
        .where.not(user_id: self.created_by_id)
        .order(:created_at)
        .then { |posts| posts.uniq(&:user_id) }
  end
end
