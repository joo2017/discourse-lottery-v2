class LotteryManager
  def initialize(lottery)
    @lottery = lottery
    @topic = lottery.topic
  end

  def perform_draw
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Starting draw for lottery ##{@lottery.id}.")
    
    unless @lottery.status == Lottery::STATUSES[:running]
      Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Lottery ##{@lottery.id} is not in 'running' status. Aborting.")
      return
    end
    
    winners = find_winners
    
    if winners.blank?
      Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] No valid winners found. Aborting draw.")
      # Optional: Update status to cancelled if no one participates.
      # @lottery.update!(status: Lottery::STATUSES[:cancelled])
      return
    end
    
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Found #{winners.count} winner(s): #{winners.map{|w| w[:username]}.join(', ')}")

    update_lottery(winners)
    announce_winners(winners)
    send_notifications(winners)
    update_topic
    
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Draw completed successfully for lottery ##{@lottery.id}.")
  end

  private

  def find_winners
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Finding winners...")
    if @lottery.specific_floors.present?
      Rails.logger.warn("LOTTERY_DEBUG: -> Method: by specific floors (#{@lottery.specific_floors}).")
      find_winners_by_floor
    else
      Rails.logger.warn("LOTTERY_DEBUG: -> Method: by random selection.")
      find_winners_by_random
    end
  end

  def find_winners_by_floor
    floors = @lottery.specific_floors.split(',').map(&:to_i).uniq
    
    posts = Post.where(topic_id: @topic.id, post_number: floors)
                .where.not(user_id: @lottery.created_by_id)
                .order(:post_number)
    
    winners = posts.map { |p| { user_id: p.user_id, username: p.user.username, post_number: p.post_number } }
    Rails.logger.warn("LOTTERY_DEBUG: -> Found #{winners.count} winners from specified floors.")
    winners
  end

  def find_winners_by_random
    participants = Post.where(topic_id: @topic.id)
                       .where("post_number > 1")
                       .where.not(user_id: @lottery.created_by_id)
                       .order(:created_at)
    
    if participants.empty?
      Rails.logger.warn("LOTTERY_DEBUG: -> No participants found for random draw.")
      return []
    end
    
    unique_participants_posts = participants.uniq(&:user_id)
    Rails.logger.warn("LOTTERY_DEBUG: -> Found #{unique_participants_posts.count} unique participants.")
    
    winners_posts = unique_participants_posts.sample(@lottery.winner_count)
    
    winners = winners_posts.map do |post|
      { user_id: post.user_id, username: post.user.username, post_number: post.post_number }
    end
    Rails.logger.warn("LOTTERY_DEBUG: -> Selected #{winners.count} winners randomly.")
    winners
  end

  def update_lottery(winners)
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Updating lottery status to 'finished' and saving winner data.")
    @lottery.update!(status: Lottery::STATUSES[:finished], winner_data: winners)
  end

  def announce_winners(winners)
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Announcing winners in topic ##{@topic.id}.")
    winner_list = winners.map do |winner|
      "- @#{winner[:username]} (##{winner[:post_number]})"
    end.join("\n")

    raw_content = "#{I18n.t("lottery_v2.draw_result.title")}\n\n#{I18n.t("lottery_v2.draw_result.winners_are")}\n#{winner_list}"
    
    PostCreator.new(Discourse.system_user, topic_id: @topic.id, raw: raw_content).create
  end

  def send_notifications(winners)
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Sending notifications to #{winners.count} winner(s).")
    winners.each do |winner|
      PostCreator.new(Discourse.system_user,
        title: I18n.t("lottery_v2.notification.won_lottery_title"),
        raw: I18n.t("lottery_v2.notification.won_lottery", lottery_name: @lottery.name, topic_title: @topic.title),
        archetype: Archetype.private_message,
        target_usernames: [winner[:username]]
      ).create
    end
  end

  def update_topic
    Rails.logger.warn("LOTTERY_DEBUG: [LotteryManager] Updating topic tags and locking topic ##{@topic.id}.")
    
    guardian = Guardian.new(Discourse.system_user)
    tag_names = @topic.tags.pluck(:name) - ["抽奖中"] + ["已开奖"]
    
    TopicTag.transaction do
      @topic.topic_tags.destroy_all
      tag_names.uniq.each do |name|
        tag = Tag.find_or_create_by_name(name)
        TopicTag.create!(topic: @topic, tag: tag)
      end
    end
    
    @topic.update(closed: true)
  end
end
