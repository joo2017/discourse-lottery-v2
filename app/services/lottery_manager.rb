class LotteryManager
  def initialize(lottery)
    @lottery = lottery
    @topic = lottery.topic
  end

  def perform_draw
    return unless @lottery.running?

    winners = find_winners
    return if winners.empty?

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

    # Note: This simple version doesn't handle invalid floors. The fallback logic can be added here.
    posts.map { |p| { user_id: p.user_id, username: p.user.username, post_number: p.post_number } }
  end

  def find_winners_by_random
    participants = Post.where(topic_id: @topic.id)
                       .where("post_number > 1")
                       .where.not(user_id: @lottery.created_by_id)
                       .order(:created_at)
                       .select("DISTINCT ON (user_id) user_id, post_number")
    
    return [] if participants.empty?

    winners_data = participants.sample(@lottery.winner_count)
    
    winners_data.map do |p|
      { user_id: p.user_id, username: User.find(p.user_id).username, post_number: p.post_number }
    end
  end

  def update_lottery(winners)
    @lottery.update!(status: :finished, winner_data: winners)
  end

  def announce_winners(winners)
    winner_list = winners.map do |winner|
      "- @#{winner[:username]} (##{winner[:post_number]})"
    end.join("\n")

    raw_content = I18n.t("lottery_v2.draw_result.title") + "\n\n" +
                  I18n.t("lottery_v2.draw_result.winners_are") + "\n" +
                  winner_list

    PostCreator.new(Discourse.system_user,
      topic_id: @topic.id,
      raw: raw_content
    ).create
  end

  def send_notifications(winners)
    winners.each do |winner|
      PostCreator.new(Discourse.system_user,
        title: I18n.t("lottery_v2.notification.won_lottery_title"),
        raw: I18n.t("lottery_v2.notification.won_lottery", lottery_name: @lottery.name, topic_title: @topic.title, topic_url: @topic.url),
        archetype: Archetype.private_message,
        target_usernames: winner[:username]
      ).create
    end
  end

  def update_topic
    tags_to_remove = ["抽奖中"]
    tags_to_add = ["已开奖"]
    
    DiscourseTagging.retag_topic_by_names(@topic, Tag.where(name: tags_to_remove), Tag.where(name: tags_to_add))
    
    @topic.update(closed: true, archived: false)
  end
end
