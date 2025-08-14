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

  # --- START: 最终的查询逻辑修复 ---
  def find_winners_by_random
    # 1. 找到所有有效回复，按时间排序
    valid_posts = Post.where(topic_id: @topic.id)
                      .where("post_number > 1")
                      .where.not(user_id: @lottery.created_by_id)
                      .order(:created_at)

    return [] if valid_posts.empty?

    # 2. 在 Ruby 中进行去重，确保每个用户只保留第一次的回复
    unique_participants_posts = valid_posts.uniq(&:user_id)
    
    # 3. 从去重后的参与者中随机抽取中奖者
    winners_posts = unique_participants_posts.sample(@lottery.winner_count)
    
    # 4. 格式化中奖者数据
    winners_posts.map do |post|
      { user_id: post.user_id, username: post.user.username, post_number: post.post_number }
    end
  end
  # --- END: 最终的查询逻辑修复 ---

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

  def update_topic
    existing_tags = @topic.tags.pluck(:name)
    tags_to_add = (["已开奖"] + existing_tags).uniq
    tags_to_remove = ["抽奖中"]
    
    DiscourseTagging.retag_topic_by_names(@topic, Guardian.new(Discourse.system_user), tags_to_add - tags_to_remove)
    
    @topic.update(closed: true)
  end
end
