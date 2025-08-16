class Lottery < ActiveRecord::Base
  self.table_name = 'lotteries'

  belongs_to :topic
  belongs_to :user, foreign_key: :created_by_id

  # --- 手动实现 Enum 功能以确保兼容性 ---
  STATUSES = { running: 0, finished: 1, cancelled: 2 }.with_indifferent_access.freeze
  DRAW_TYPES = { random: 1, specific_floor: 2 }.with_indifferent_access.freeze
  INSUFFICIENT_PARTICIPANTS_ACTIONS = { draw_anyway: 0, cancel: 1 }.with_indifferent_access.freeze

  scope :running, -> { where(status: STATUSES[:running]) }

  def status_name; STATUSES.key(self.status); end
  STATUSES.each_key { |name| define_method("#{name}?") { self.status == STATUSES[name] } }

  def draw_type_name; DRAW_TYPES.key(self.draw_type); end
  DRAW_TYPES.each_key { |name| define_method("#{name}?") { self.draw_type == DRAW_TYPES[name] } }

  def insufficient_participants_action_name; INSUFFICIENT_PARTICIPANTS_ACTIONS.key(self.insufficient_participants_action); end
  # --- Enum 手动实现结束 ---

  def participating_user_count
    cache_duration = SiteSetting.lottery_v2_cache_duration.seconds
    cache_key = "discourse_lottery_v2:participants:#{id}"
    
    Rails.cache.fetch(cache_key, expires_in: cache_duration) do
      Post.where(topic_id: self.topic_id)
          .where("post_number > 1")
          .where.not(user_id: self.created_by_id)
          .distinct
          .count(:user_id)
    end
  end

  def valid_participants_with_user
    Post.includes(:user)
        .where(topic_id: self.topic_id)
        .where("post_number > 1")
        .where.not(user_id: self.created_by_id)
        .order(:created_at)
        .then { |posts| posts.uniq(&:user_id) }
  end
end
