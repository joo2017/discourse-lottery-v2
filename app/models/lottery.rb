class Lottery < ActiveRecord::Base
  self.table_name = 'lotteries'

  belongs_to :topic
  belongs_to :user, foreign_key: :created_by_id

  STATUSES = { running: 0, finished: 1, cancelled: 2 }.freeze
  DRAW_TYPES = { by_time: 1, by_reply: 2 }.freeze

  def status_name
    STATUSES.key(self.status)
  end

  def draw_type_name
    DRAW_TYPES.key(self.draw_type)
  end

  validates :topic_id, presence: true, uniqueness: true
  validates :post_id, presence: true
  validates :created_by_id, presence: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :prize, presence: true
  validates :winner_count, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :draw_type, presence: true, inclusion: { in: DRAW_TYPES.values }
  validates :status, presence: true, inclusion: { in: STATUSES.values }

  def participating_user_count
    Post.where(topic_id: self.topic_id)
        .where("post_number > 1")
        .where.not(user_id: self.created_by_id)
        .distinct.count(:user_id)
  end
end
