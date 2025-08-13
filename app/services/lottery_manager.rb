class LotteryManager
  def initialize(lottery)
    @lottery = lottery
    @topic = lottery.topic
  end

  def perform_draw
    return unless @lottery.running?
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
    participants = Post.where(topic_id: @topic.id)
                       .where("post_number > 1")
                       .where.not(user_id: @lottery.created_by_id)
                       .order(:created_at)
                       .distinct
                       .pluck(:user_id, :post_number)
    
    return [] if participants.empty?

    unique_participants = participants.uniq { |p| p[0] }
    
    winners_data = unique_participants.sample(@lottery.winner_count)
    
    User.where(id: winners_data.map(&:first)).map do |user|
      post_number = winners_data.assoc(user.id)[1]
      { user_id: user.id, username: user.username, post_number: post_number }
    end
  end

  def update_lottery(winners)
    @lottery.update!(status: :finished, winner_data: winners)
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
        raw: I18n.t("lottery_v2.notification.won_lottery", lottery_name: @lottery.name, topic_title: @topic.title, topic_url: @topic.url),
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
