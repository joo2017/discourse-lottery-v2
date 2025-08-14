class LotteryManager
  def initialize(lottery)
    @lottery = lottery
    @topic = lottery.topic
  end

  def perform_draw
    return unless @lottery.status == Lottery::STATUSES[:running]
    
    winners = find_winners
    return if winners.blank?

    update_lottery(winners)
    announce_winners(winners)
    send_notifications(winners)
    update_topic
  end

  private

  def find_winners
    if @lottery.specific_floors.present?
      find_winners_by_floor
    else
      find_winners_by_random
    end
  end

  def find_winners_by_floor
    floors = @lottery.specific_floors.split(',').map(&:to_i).uniq
    
    posts = Post.where(topic_id: @topic.id, post_number: floors)
                .where.not(user_id: @lottery.created_by_id)
                .order(:post_number)
    
    posts.map { |p| { user_id: p.user_id, username: p.user.username, post_number: p.post_number } }
  end

  def find_winners_by_random
    valid_posts = Post.where(topic_id: @topic.id)
                      .where("post_number > 1")
                      .where.not(user_id: @lottery.created_by_id)
                      .order(:created_at)

    return [] if valid_posts.empty?

    unique_participants_posts = valid_posts.uniq(&:user_id)
    
    winners_posts = unique_participants_posts.sample(@lottery.winner_count)
    
    winners_posts.map do |post|
      { user_id: post.user_id, username: post.user.username, post_number: post.post_number }
    end
  end

  def update_lottery(winners)
    @lottery.update!(status: Lottery::STATUSES[:finished], winner_data: winners)
  end

  def announce_winners(winners)
    winner_list = winners.map do |winner|
      "- @#{winner[:username]} (##{winner[:post_number]})"
    end.join("\n")

    raw_content = "#{I18n.t("lottery_v2.draw_result.title")}\n\n#{I18n.t("lottery_v2.draw_result.winners_are")}\n#{winner_list}"
    
    PostCreator.new(Discourse.system_user, topic_id: @topic.id, raw: raw_content).create
  end

  def send_notifications(winners)
    winners.each do |winner|
      PostCreator.new(Discourse.system_user,
        title: I18n.t("lottery_v2.notification.won_lottery_title"),
        raw: I18n.t("lottery_v2.notification.won_lottery", lottery_name: @lottery.name, topic_title: @topic.title),
        archetype: Archetype.private_message,
        target_usernames: [winner[:username]]
      ).create
    end
  end

  # --- START: 最终的 API 修复 ---
  def update_topic
    # 使用现代 Discourse 推荐的 TopicTag Guardian 来修改标签
    guardian = Guardian.new(Discourse.system_user)
    tag_names = @topic.tags.pluck(:name) - ["抽奖中"] + ["已开奖"]
    
    TopicTag.transaction do
      @topic.topic_tags.destroy_all
      tag_names.uniq.each do |name|
        tag = Tag.find_or_create_by_name(name)
        TopicTag.create!(topic: @topic, tag: tag)
      end
    end
    
    # 锁定主题
    @topic.update(closed: true)
  end
  # --- END: 最终的 API 修复 ---
end
