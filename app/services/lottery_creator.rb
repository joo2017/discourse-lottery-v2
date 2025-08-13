class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    return if Lottery.exists?(topic_id: @topic.id)
    raw = @post.raw
    params = parse_raw(raw)
    return if params.values.any?(&:nil?)

    Lottery.create!(
      topic_id: @topic.id,
      post_id: @post.id,
      created_by_id: @user.id,
      name: params[:name],
      prize: params[:prize],
      winner_count: params[:winner_count],
      draw_type: params[:draw_type], # 已在 parse_raw 中设置为正确的整数
      draw_at: params[:draw_at],
      draw_reply_count: params[:draw_reply_count],
      specific_floors: params[:specific_floors],
      description: params[:description],
      extra_info: params[:extra_info],
      status: Lottery::STATUSES[:running] # 使用常量
    )
    add_tag("抽奖中")
  end

  private

  def parse_raw(raw)
    params = {}
    params[:name] = raw[/\[lottery-name\](.*?)\[\/lottery-name\]/m, 1]&.strip
    params[:prize] = raw[/\[lottery-prize\](.*?)\[\/lottery-prize\]/m, 1]&.strip
    params[:winner_count] = raw[/\[lottery-winners\](.*?)\[\/lottery-winners\]/m, 1]&.to_i
    
    draw_type_str = raw[/\[lottery-draw-type\](.*?)\[\/lottery-draw-type\]/m, 1]&.strip
    if draw_type_str == "时间开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_time] # 使用常量
      draw_at_str = raw[/\[lottery-condition\](.*?)\[\/lottery-condition\]/m, 1]&.strip
      params[:draw_at] = Time.zone.parse(draw_at_str) rescue nil
    elsif draw_type_str == "回复数开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_reply] # 使用常量
      params[:draw_reply_count] = raw[/\[lottery-condition\](.*?)\[\/lottery-condition\]/m, 1]&.to_i
    end

    params[:specific_floors] = raw[/\[lottery-floors\](.*?)\[\/lottery-floors\]/m, 1]&.strip
    params[:description] = raw[/\[lottery-description\](.*?)\[\/lottery-description\]/m, 1]&.strip
    params[:extra_info] = raw[/\[lottery-extra\](.*?)\[\/lottery-extra\]/m, 1]&.strip

    params
  end

  def add_tag(tag_name)
    tag = Tag.find_or_create_by!(name: tag_name)
    DiscourseTagging.tag_topic_by_names(@topic, Guardian.new(Discourse.system_user), [tag_name])
  end
end
