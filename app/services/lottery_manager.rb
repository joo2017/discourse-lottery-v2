class LotteryManager
  def initialize(lottery)
    @lottery = lottery
    @topic = lottery.topic
  end

  def perform_draw
    return unless @lottery.running?
    
    winners = find_winners
    
    # 如果没有找到任何有效的中奖者，则中止抽奖，避免后续操作出错
    if winners.blank?
      Rails.logger.warn("LOTTERY_DRAW_ABORTED: No valid winners found for lottery ##{@lottery.id}.")
      return
    end

    # 修正：使用数据库事务来确保开奖流程的原子性
    # 如果其中任何一步失败（例如发帖API变更），所有数据库操作都会回滚
    ActiveRecord::Base.transaction do
      update_lottery(winners)
      announce_winners(winners)
      send_notifications(winners)
      update_topic
    end
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
    target_floors = @lottery.specific_floors.split(',').map(&:to_i).uniq.sort
    
    # 查找所有目标楼层的有效帖子（非楼主发布）
    valid_posts_map = Post.where(topic_id: @topic.id, post_number: target_floors)
                          .where.not(user_id: @lottery.created_by_id)
                          .index_by(&:post_number)

    winners = []
    
    target_floors.each do |floor|
      post = valid_posts_map[floor]
      if post.present?
        winners << { user_id: post.user_id, username: post.user.username, post_number: post.post_number }
      else
        # 修正：实现指定楼层无效时的回退策略
        fallback_action = SiteSetting.lottery_v2_floor_fallback
        if fallback_action == 'next'
          # 寻找下一个有效的楼层作为替补（不能是已中奖的用户或已检查过的楼层）
          existing_winner_ids = winners.map { |w| w[:user_id] }
          existing_post_numbers = winners.map { |w| w[:post_number] }

          next_valid_post = Post.where(topic_id: @topic.id)
                                .where("post_number > ?", floor)
                                .where.not(user_id: @lottery.created_by_id)
                                .where.not(user_id: existing_winner_ids)
                                .where.not(post_number: existing_post_numbers)
                                .order(:post_number)
                                .first
          if next_valid_post
            winners << { user_id: next_valid_post.user_id, username: next_valid_post.user.username, post_number: next_valid_post.post_number }
          end
        end
        # 如果 fallback_action 是 'void' (默认)，则什么都不做，该中奖名额作废
      end
    end
    
    # 再次去重，以防 'next' 策略找到重复的用户
    winners.uniq! { |w| w[:user_id] }
    # 确保最终获奖人数不超过设定的总数
    winners.take(@lottery.winner_count)
  end

  def find_winners_by_random
    # 筛选出所有有效参与者（排除楼主，每人只计最早的回复）
    participant_posts = Post.where(topic_id: @topic.id)
                            .where("post_number > 1")
                            .where.not(user_id: @lottery.created_by_id)
                            .order(:created_at)
                            .uniq(&:user_id)

    return [] if participant_posts.empty?

    # 修正：抽奖人数取 设定获奖人数 和 有效参与人数 中的较小值
    draw_count = [@lottery.winner_count, participant_posts.size].min
    
    winners_posts = participant_posts.sample(draw_count)
    
    winners_posts.map do |post|
      { user_id: post.user_id, username: post.user.username, post_number: post.post_number }
    end
  end

  def update_lottery(winners)
    # 使用 `update!` 在失败时抛出异常以触发事务回滚
    @lottery.update!(status: :finished, winner_data: winners.to_json)
  end

  def announce_winners(winners)
    winner_list = winners.map do |winner|
      "- @#{winner[:username]} (##{winner[:post_number]})"
    end.join("\n")

    raw_content = "#{I18n.t("lottery_v2.draw_result.title")}\n\n#{I18n.t("lottery_v2.draw_result.winners_are")}\n#{winner_list}"
    
    # 使用 `create!`
    PostCreator.new(Discourse.system_user, topic_id: @topic.id, raw: raw_content).create!
  end

  def send_notifications(winners)
    winners.each do |winner|
      user = User.find_by(id: winner[:user_id])
      next unless user

      # 使用 `create!`
      PostCreator.new(Discourse.system_user,
        title: I18n.t("lottery_v2.notification.won_lottery_title"),
        # 修正：传入 topic_url
        raw: I18n.t("lottery_v2.notification.won_lottery", lottery_name: @lottery.name, topic_title: @topic.title, topic_url: @topic.url),
        archetype: Archetype.private_message,
        target_usernames: [user.username]
      ).create!
    end
  end

  def update_topic
    # 修正：使用更可靠的 DiscourseTagging.synchronize_tags 方法
    current_tags = @topic.tags.pluck(:name)
    new_tags = (current_tags - ["抽奖中"]) + ["已开奖"]
    
    DiscourseTagging.synchronize_tags(@topic, Tag.where(name: new_tags), Guardian.new(Discourse.system_user))
    
    # 使用 `update!`
    @topic.update!(closed: true)
  end
end
