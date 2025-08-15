class LotteryManager
  def initialize(lottery)
    @lottery = lottery
    @topic = lottery.topic
  end

  def perform_draw
    return unless @lottery.running?
    
    participant_count = @lottery.participating_user_count
    min_participants = SiteSetting.lottery_v2_min_participants
    
    if participant_count < min_participants
      return handle_no_winners("Not enough participants. Required: #{min_participants}, Actual: #{participant_count}")
    end

    begin
      Lottery.transaction do
        winners = find_winners
        return handle_no_winners("No valid participants found after filtering") if winners.blank?
        
        validated_winners = validate_winners(winners)
        return handle_no_winners("No valid winners after validation (e.g., suspended users)") if validated_winners.blank?

        update_lottery(validated_winners)
        announce_winners(validated_winners)
        send_notifications(validated_winners) if SiteSetting.lottery_v2_send_notifications
        update_topic if SiteSetting.lottery_v2_auto_close_topic
        
        create_audit_log('draw_completed', { winners_count: validated_winners.size })
      end
    rescue => e
      handle_draw_error(e)
    end
  end

  private
  
  def find_winners
    @lottery.specific_floors.present? ? find_winners_by_floor : find_winners_by_random
  end

  def find_winners_by_random
    participants = @lottery.valid_participants_with_user
    return [] if participants.empty?
    participants.sample(@lottery.winner_count).map { |post| format_winner_data(post) }
  end

  def find_winners_by_floor
    floors = @lottery.specific_floors.split(/[,，\s]+/).map(&:to_i).select { |n| n > 1 }.uniq.sort
    return [] if floors.empty?
    
    posts_map = Post.includes(:user).where(topic_id: @topic.id, post_number: floors)
                    .where.not(user_id: @lottery.created_by_id)
                    .index_by(&:post_number)
    
    winners = []
    
    floors.each do |floor|
      post = posts_map[floor]
      if post
        winners << post
      elsif SiteSetting.lottery_v2_floor_fallback == 'next'
        existing_winner_ids = winners.map(&:user_id)
        next_post = Post.includes(:user)
                        .where(topic_id: @topic.id)
                        .where("post_number > ?", floor)
                        .where.not(user_id: @lottery.created_by_id)
                        .where.not(user_id: existing_winner_ids)
                        .order(:post_number)
                        .first
        winners << next_post if next_post
      end
    end
    
    winners.uniq(&:user_id).take(@lottery.winner_count).map { |p| format_winner_data(p) }
  end

  def validate_winners(winners)
    winners.select do |winner|
      user = User.find_by(id: winner[:user_id])
      is_valid = user && !user.suspended? && !user.staged?
      Rails.logger.warn("LOTTERY_INVALID_WINNER: User #{winner[:user_id]} is invalid") unless is_valid
      is_valid
    end
  end

  def format_winner_data(post)
    { user_id: post.user_id, username: post.user.username, post_number: post.post_number, user_title: post.user&.title }
  end

  def update_lottery(winners)
    @lottery.update!(status: Lottery::STATUSES[:finished], winner_data: winners)
  end
  
  def announce_winners(winners)
    winner_list = winners.map do |winner|
      "- @#{winner[:username]} (##{winner[:post_number]})"
    end.join("\n")
    raw_content = "#{I18n.t("lottery_v2.draw_result.title")}\n\n#{I18n.t("lottery_v2.draw_result.winners_are")}\n#{winner_list}"
    PostCreator.new(Discourse.system_user, topic_id: @topic.id, raw: raw_content).create!
  end
  
  def send_notifications(winners)
    winners.each do |winner|
      user = User.find_by(id: winner[:user_id])
      next unless user
      PostCreator.new(Discourse.system_user,
        title: I18n.t("lottery_v2.notification.won_lottery_title"),
        raw: I18n.t("lottery_v2.notification.won_lottery", 
                    lottery_name: @lottery.name, 
                    topic_title: @topic.title, 
                    topic_url: @topic.url),
        archetype: Archetype.private_message,
        target_usernames: [user.username]
      ).create!
    end
  end

  # 【重要】修正：使用新的 DiscourseTagging API
  def update_topic
    guardian = Guardian.new(Discourse.system_user)
    tag_names_to_add = ["已开奖"]
    tag_names_to_remove = ["抽奖中"]

    # 使用新的、更可靠的 API
    DiscourseTagging.add_tags(tag_names_to_add, @topic, guardian)
    DiscourseTagging.remove_tags(tag_names_to_remove, @topic, guardian)
    
    @topic.update!(closed: true)
  end

  def handle_no_winners(reason)
    @lottery.update!(status: Lottery::STATUSES[:cancelled])
    announce_cancellation
    create_audit_log('draw_cancelled', { reason: reason })
  end
  
  def announce_cancellation
    PostCreator.new(Discourse.system_user, topic_id: @topic.id, raw: I18n.t("lottery_v2.draw_result.no_participants")).create!
  end

  def handle_draw_error(error)
    Rails.logger.error("LOTTERY_DRAW_ERROR: Lottery #{@lottery.id} - #{error.class.name}: #{error.message}\n#{error.backtrace.first(10).join("\n")}")
    create_audit_log('draw_failed', { error: error.message })
  end

  def create_audit_log(action, data = {})
    Rails.logger.info("LOTTERY_AUDIT: lottery_id=#{@lottery.id}, action=#{action}, data=#{data.to_json}")
  end
end
